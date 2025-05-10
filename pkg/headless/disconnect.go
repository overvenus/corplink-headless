package headless

import (
	"context"
	"fmt"
	"log"

	"github.com/overvenus/corplink-headless/pkg/proto"
)

type disconnectState struct{}

func Disconnect() Step {
	return &disconnectState{}
}

func (s *disconnectState) disconnectVPN(ctx context.Context, cli State) error {
	resp, err := cli.DisconnectVpn(ctx, &proto.EmptyRequest{})
	if err != nil {
		return fmt.Errorf("failed to disconnectVPN: %w", err)
	}
	if resp.Code != 0 {
		return fmt.Errorf("failed to disconnectVPN: %s", resp.Message)
	}
	return nil
}

func (s *disconnectState) Execute(ctx context.Context, cli State) error {
	connected, err := GetVpnStatus(ctx, cli)
	if err != nil {
		log.Printf("failed to get VPN status: %s", err)
	}
	if connected {
		log.Println("disconnecting VPN ...")
		return s.disconnectVPN(ctx, cli)
	}
	return nil
}
