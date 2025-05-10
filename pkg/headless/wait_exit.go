package headless

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type waitExit struct{}

func WaitExit() Step {
	return &waitExit{}
}

func (s *waitExit) waitSignal() chan os.Signal {
	exitSig := make(chan os.Signal, 1)
	signal.Notify(exitSig,
		syscall.SIGHUP,
		syscall.SIGINT,
		syscall.SIGTERM,
		syscall.SIGQUIT)
	return exitSig
}

func (s *waitExit) Execute(ctx context.Context, cli State) error {
	exitSig := s.waitSignal()
	defer signal.Stop(exitSig)
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case sig := <-exitSig:
			log.Printf("received exit signal: %s", sig)
			return nil
		case <-ticker.C:
			connected, err := GetVpnStatus(ctx, cli)
			if err != nil {
				log.Printf("failed to get VPN status: %s", err)
			}
			if !connected {
				log.Println("VPN disconnected")
			}
		}
	}
}
