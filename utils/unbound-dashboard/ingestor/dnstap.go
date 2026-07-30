package ingestor

import (
	"encoding/binary"
	"fmt"
	"net"
	"os"
	"time"

	"unbound-dashboard/core"
	"unbound-dashboard/database"
)

const (
	CONTROL_ACCEPT = 0x01
	CONTROL_START  = 0x02
	CONTROL_STOP   = 0x03
	CONTROL_READY  = 0x04
	CONTROL_FINISH = 0x05

	CONTROL_FIELD_CONTENT_TYPE = 0x01
	CONTENT_TYPE_DNSTAP        = "protobuf:dnstap.Dnstap"

	DNSTAP_FIELD_MESSAGE = 0x0e

	MSG_FIELD_QUERY_MESSAGE    = 0x0a // field 10
	MSG_FIELD_RESPONSE_MESSAGE = 0x0e // field 14
)

type DnstapReader struct {
	socketPath string
}

func NewDnstapReader(p string) *DnstapReader {
	return &DnstapReader{socketPath: p}
}

func (d *DnstapReader) GetPath() string { return d.socketPath }

func (d *DnstapReader) Start(db *database.Database) error {
	if _, err := os.Stat(d.socketPath); err == nil {
		os.Remove(d.socketPath)
	}

	listener, err := net.Listen("unix", d.socketPath)
	if err != nil {
		return fmt.Errorf("创建 socket 失败: %w", err)
	}
	defer listener.Close()

	os.Chmod(d.socketPath, 0777)

	fmt.Printf("✅ DNSTap socket 已创建: %s\n", d.socketPath)
	fmt.Println("👂 等待 Unbound 连接...")

	for {
		conn, err := listener.Accept()
		if err != nil {
			return fmt.Errorf("接受连接失败: %w", err)
		}
		fmt.Println("✅ Unbound 已连接")

		err = d.handleConnection(conn, db)
		conn.Close()
		if err != nil {
			fmt.Printf("⚠️  连接断开: %v\n", err)
			fmt.Println("👂 等待 Unbound 重新连接...")
			continue
		}
		return nil
	}
}

func (d *DnstapReader) handleConnection(conn net.Conn, db *database.Database) error {
	fmt.Println("🤝 开始 Frame Streams 双向握手...")

	ctype, _, err := readHandshakeFrame(conn)
	if err != nil {
		return fmt.Errorf("读取 READY 失败: %w", err)
	}
	if ctype != CONTROL_READY {
		return fmt.Errorf("期望 READY(0x%02x)，收到 0x%02x", CONTROL_READY, ctype)
	}

	if err := sendHandshakeFrame(conn, CONTROL_ACCEPT, []string{CONTENT_TYPE_DNSTAP}); err != nil {
		return fmt.Errorf("发送 ACCEPT 失败: %w", err)
	}

	ctype, _, err = readHandshakeFrame(conn)
	if err != nil {
		return fmt.Errorf("读取 START 失败: %w", err)
	}
	if ctype != CONTROL_START {
		return fmt.Errorf("期望 START(0x%02x)，收到 0x%02x", CONTROL_START, ctype)
	}
	fmt.Println("📥 收到 START，开始接收数据帧...")

	count := 0

	for {
		var frameLen uint32
		if err := binary.Read(conn, binary.BigEndian, &frameLen); err != nil {
			return fmt.Errorf("读取帧长度失败: %w", err)
		}

		if frameLen == 0 {
			ctype, _, err := readCtrlBody(conn)
			if err != nil {
				return fmt.Errorf("读取控制帧失败: %w", err)
			}
			if ctype == CONTROL_STOP {
				fmt.Println("🛑 收到 STOP 控制帧")
				if err := sendHandshakeFrame(conn, CONTROL_FINISH, nil); err != nil {
					fmt.Printf("⚠️  发送 FINISH 失败: %v\n", err)
				}
				return nil
			}
			continue
		}

		frame := make([]byte, frameLen)
		if _, err := readFull(conn, frame); err != nil {
			return fmt.Errorf("读取数据帧失败: %w", err)
		}

		rec := parseDnstapFrame(frame)
		if rec != nil {
			err := db.InsertRecord(*rec)
			if err != nil {
				fmt.Printf("❌ 插入数据库失败: %v\n", err)
			} else {
				count++
				}
			}
		}
	}
}

func sendHandshakeFrame(conn net.Conn, frameType uint32, contentTypes []string) error {
	var frame []byte
	b := make([]byte, 4)

	binary.BigEndian.PutUint32(b, 0)
	frame = append(frame, b...)

	var ctrlData []byte
	binary.BigEndian.PutUint32(b, frameType)
	ctrlData = append(ctrlData, b...)

	for _, ct := range contentTypes {
		binary.BigEndian.PutUint32(b, CONTROL_FIELD_CONTENT_TYPE)
		ctrlData = append(ctrlData, b...)
		binary.BigEndian.PutUint32(b, uint32(len(ct)))
		ctrlData = append(ctrlData, b...)
		ctrlData = append(ctrlData, []byte(ct)...)
	}

	binary.BigEndian.PutUint32(b, uint32(len(ctrlData)))
	frame = append(frame, b...)
	frame = append(frame, ctrlData...)

	_, err := conn.Write(frame)
	return err
}

func readHandshakeFrame(conn net.Conn) (uint32, []string, error) {
	var escape uint32
	if err := binary.Read(conn, binary.BigEndian, &escape); err != nil {
		return 0, nil, fmt.Errorf("读取 escape 失败: %w", err)
	}
	if escape != 0 {
		return 0, nil, fmt.Errorf("escape 不是 0: %d", escape)
	}
	return readCtrlBody(conn)
}

func readCtrlBody(conn net.Conn) (uint32, []string, error) {
	var ctrlLen uint32
	if err := binary.Read(conn, binary.BigEndian, &ctrlLen); err != nil {
		return 0, nil, fmt.Errorf("读取控制帧长度失败: %w", err)
	}

	if ctrlLen < 4 {
		return 0, nil, fmt.Errorf("控制帧长度太短: %d", ctrlLen)
	}

	ctrlData := make([]byte, ctrlLen)
	if _, err := readFull(conn, ctrlData); err != nil {
		return 0, nil, fmt.Errorf("读取控制帧数据失败: %w", err)
	}

	ctrlType := binary.BigEndian.Uint32(ctrlData[0:4])

	var contentTypes []string
	offset := 4
	for offset+8 <= len(ctrlData) {
		fieldType := binary.BigEndian.Uint32(ctrlData[offset : offset+4])
		offset += 4
		if fieldType != CONTROL_FIELD_CONTENT_TYPE {
			break
		}
		fieldLen := binary.BigEndian.Uint32(ctrlData[offset : offset+4])
		offset += 4
		if offset+int(fieldLen) > len(ctrlData) {
			break
		}
		contentTypes = append(contentTypes, string(ctrlData[offset:offset+int(fieldLen)]))
		offset += int(fieldLen)
	}

	return ctrlType, contentTypes, nil
}

func parseDnstapFrame(data []byte) *core.QueryRecord {
	msgBytes := getProtobufBytes(data, DNSTAP_FIELD_MESSAGE)
	if msgBytes == nil {
		return nil
	}

	var dnsPayload []byte
	var isResponse bool

	dnsPayload = getProtobufBytes(msgBytes, MSG_FIELD_RESPONSE_MESSAGE)
	if dnsPayload != nil {
		isResponse = true
	} else {
		dnsPayload = getProtobufBytes(msgBytes, MSG_FIELD_QUERY_MESSAGE)
		if dnsPayload != nil {
			isResponse = false
		}
	}

	if dnsPayload == nil {
		return nil
	}

	domain, qtype, rcode := parseDNSPacket(dnsPayload, isResponse)
	if domain == "" {
		return nil
	}

	rec := &core.QueryRecord{
		Domain:    domain,
		QType:     qtype,
		RCode:     rcode,
		Response:  "dnstap",
		Timestamp: float64(time.Now().Unix()),
	}

	if rcode != "" && rcode != "NOERROR" && rcode != "SERVFAIL" {
		rec.Blocked = true
		rec.BlockReason = rcode
	}

	return rec
}

func parseDNSPacket(data []byte, isResponse bool) (domain string, qtype string, rcode string) {
	if len(data) < 12 {
		return "", "", ""
	}

	rcodeInt := int(data[3] & 0x0F)
	rcode = rcodeToName(rcodeInt)

	qdcount := int(binary.BigEndian.Uint16(data[4:6]))
	if qdcount == 0 {
		return "", "", rcode
	}

	offset := 12
	domain, offset = decodeDNSName(data, offset)

	if offset+2 <= len(data) {
		qtypeInt := binary.BigEndian.Uint16(data[offset : offset+2])
		qtype = qtypeToName(qtypeInt)
	}

	return domain, qtype, rcode
}

func decodeDNSName(data []byte, offset int) (string, int) {
	var parts []string
	jumped := false
	returnOffset := offset
	for offset < len(data) {
		length := int(data[offset])
		if length == 0 {
			offset++
			break
		}
		if length&0xC0 == 0xC0 {
			if offset+1 >= len(data) {
				break
			}
			ptr := int(binary.BigEndian.Uint16(data[offset:offset+2]) & 0x3FFF)
			if !jumped {
				returnOffset = offset + 2
			}
			offset = ptr
			jumped = true
			continue
		}
		offset++
		if offset+length > len(data) {
			break
		}
		parts = append(parts, string(data[offset:offset+length]))
		offset += length
	}
	if jumped {
		return joinParts(parts), returnOffset
	}
	return joinParts(parts), offset
}

func joinParts(parts []string) string {
	result := ""
	for i, p := range parts {
		if i > 0 {
			result += "."
		}
		result += p
	}
	return result
}

func getProtobufBytes(data []byte, targetField int) []byte {
	offset := 0
	for offset < len(data) {
		tag, n := decodeVarint(data[offset:])
		if n == 0 {
			return nil
		}
		offset += n
		fieldNum := int(tag >> 3)
		wireType := int(tag & 0x07)
		switch wireType {
		case 0:
			_, n := decodeVarint(data[offset:])
			if n == 0 {
				return nil
			}
			offset += n
		case 2:
			length, n := decodeVarint(data[offset:])
			if n == 0 {
				return nil
			}
			offset += n
			if fieldNum == targetField {
				if offset+int(length) > len(data) {
					return nil
				}
				return data[offset : offset+int(length)]
			}
			offset += int(length)
		case 5:
			if fieldNum == targetField {
				if offset+4 > len(data) {
					return nil
				}
				return data[offset : offset+4]
			}
			offset += 4
		case 1:
			if fieldNum == targetField {
				if offset+8 > len(data) {
					return nil
				}
				return data[offset : offset+8]
			}
			offset += 8
		default:
			return nil
		}
	}
	return nil
}

func decodeVarint(data []byte) (uint64, int) {
	var val uint64
	var shift uint
	for i, b := range data {
		val |= uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			return val, i + 1
		}
		shift += 7
		if i > 9 {
			return 0, 0
		}
	}
	return 0, 0
}

func readFull(conn net.Conn, buf []byte) (int, error) {
	total := 0
	for total < len(buf) {
		n, err := conn.Read(buf[total:])
		if err != nil {
			return total, err
		}
		total += n
	}
	return total, nil
}

func qtypeToName(qtype uint16) string {
	names := map[uint16]string{
		1: "A", 2: "NS", 5: "CNAME", 6: "SOA", 12: "PTR",
		15: "MX", 16: "TXT", 28: "AAAA", 33: "SRV", 255: "ANY",
		65: "HTTPS", 257: "CAA",
	}
	if name, ok := names[qtype]; ok {
		return name
	}
	return fmt.Sprintf("TYPE%d", qtype)
}

func rcodeToName(rcode int) string {
	names := map[int]string{
		0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN",
		4: "NOTIMP", 5: "REFUSED",
	}
	if name, ok := names[rcode]; ok {
		return name
	}
	return fmt.Sprintf("RCODE%d", rcode)
}
