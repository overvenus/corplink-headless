package headless

import (
	"context"
	"log"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

// Interceptor for logging requests/responses
func unaryClientLoggerInterceptor(
	ctx context.Context,
	method string,
	req, reply any,
	cc *grpc.ClientConn,
	invoker grpc.UnaryInvoker,
	opts ...grpc.CallOption,
) error {
	if msg, ok := req.(proto.Message); ok {
		b, _ := protojson.Marshal(msg)
		log.Printf("===> %s Request: %s", method, string(b))
	}

	var header, trailer metadata.MD
	opts = append(opts,
		grpc.Header(&header),
		grpc.Trailer(&trailer),
	)

	err := invoker(ctx, method, req, reply, cc, opts...)

	if msg, ok := reply.(proto.Message); ok {
		b, _ := protojson.Marshal(msg)
		log.Printf("<=== Response: %s", string(b))
	}

	log.Printf("===> %s Sent Headers: %v", method, extractOutgoingHeaders(ctx))
	log.Printf("<=== Response Headers: %v", header)
	log.Printf("<=== Response Trailers: %v", trailer)

	if err != nil {
		log.Printf("<=== RPC Error: %v", err)
	}

	return err
}

// Helper to extract outgoing headers from context
func extractOutgoingHeaders(ctx context.Context) metadata.MD {
	md, _ := metadata.FromOutgoingContext(ctx)
	return md
}
