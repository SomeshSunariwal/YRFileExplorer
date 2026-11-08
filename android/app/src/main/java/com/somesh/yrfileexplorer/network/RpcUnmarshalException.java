package com.somesh.yrfileexplorer.network;

import java.io.IOException;

/**
 * Android equivalent of the checked decoding exception used by the DCERPC
 * library.
 */
public final class RpcUnmarshalException extends IOException {
    public RpcUnmarshalException(String message) {
        super(message);
    }

    public RpcUnmarshalException(String message, Exception cause) {
        super(message, cause);
    }
}
