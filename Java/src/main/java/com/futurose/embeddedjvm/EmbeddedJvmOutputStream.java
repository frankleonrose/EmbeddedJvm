package com.futurose.embeddedjvm;

import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;

public class EmbeddedJvmOutputStream extends OutputStream {
	public EmbeddedJvmOutputStream(String tag) {
		nativeOpen(tag);
	}

	@Override
	public void write(int b) throws IOException {
		byte[] bytes = new byte[1];
		bytes[0] = (byte)b;
		nativeWrite(bytes, 0, 1);
	}
	
	@Override
	public void write(byte[] b) throws IOException {
		nativeWrite(b, 0, b.length);
	}

	@Override
	public void write(byte[] b, int off, int len) throws IOException {
		nativeWrite(b, off, len);
	}

	@Override
	public void flush() throws IOException {
		nativeFlush();
	}
	
	@Override
	public void close() throws IOException {
		nativeClose();
	}
	
	static void redirectStandardStreams() throws Exception {
		System.setOut(new PrintStream(new EmbeddedJvmOutputStream("out")));
		System.setErr(new PrintStream(new EmbeddedJvmOutputStream("err")));
	}
	
	native void nativeWrite(byte[] bytes, int off, int len);
	native void nativeOpen(String name);
	native void nativeClose();
	native void nativeFlush();
}
