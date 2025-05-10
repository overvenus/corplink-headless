package headless

import (
	"fmt"
	"os"
	"os/user"
)

type Token struct {
	CorplinkUser  string
	CorplinkToken string
}

// NewToken creates a new Token instance by reading rpcConf file.
func NewToken(rpcConf string) (Token, error) {
	user, err := user.Current()
	if err != nil {
		return Token{}, fmt.Errorf("failed to read user name: %w", err)
	}
	token, err := os.ReadFile(rpcConf)
	if err != nil {
		return Token{}, fmt.Errorf("failed to read token file: %w", err)
	}
	if len(token) != 32 {
		return Token{}, fmt.Errorf("token file must be 32 bytes, got %d, %s", len(token), token)
	}
	return Token{
		CorplinkUser:  user.Username,
		CorplinkToken: string(token),
	}, nil
}
