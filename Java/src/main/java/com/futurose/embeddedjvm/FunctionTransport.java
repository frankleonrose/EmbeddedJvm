package com.futurose.embeddedjvm;

import java.io.UnsupportedEncodingException;
import java.util.Arrays;

import org.apache.thrift.TByteArrayOutputStream;
import org.apache.thrift.transport.TMemoryInputTransport;
import org.apache.thrift.transport.TTransport;
import org.apache.thrift.transport.TTransportException;

/**
 * Exactly TMemoryBuffer, but with reset() method to clear the buffer.
 */
class TClearableMemoryBuffer extends TTransport {
	private final int size;
	/**
	 * Create a TMemoryBuffer with an initial buffer size of <i>size</i>. The
	 * internal buffer will grow as necessary to accommodate the size of the
	 * data being written to it.
	 */
	public TClearableMemoryBuffer(int size) {
		this.size = size;
		arr_ = new TByteArrayOutputStream(size);
	}
	
	public void reset() {
		arr_ = new TByteArrayOutputStream(size);
	}
	
	@Override
	public boolean isOpen() {
		return true;
	}

	@Override
	public void open() {
		/* Do nothing */
	}

	@Override
	public void close() {
		/* Do nothing */
	}

	@Override
	public int read(byte[] buf, int off, int len) {
		byte[] src = arr_.get();
		int amtToRead = (len > arr_.len() - pos_ ? arr_.len() - pos_ : len);
		if (amtToRead > 0) {
			System.arraycopy(src, pos_, buf, off, amtToRead);
			pos_ += amtToRead;
		}
		return amtToRead;
	}

	@Override
	public void write(byte[] buf, int off, int len) {
		arr_.write(buf, off, len);
	}

	/**
	 * Output the contents of the memory buffer as a String, using the supplied
	 * encoding
	 * 
	 * @param enc
	 *            the encoding to use
	 * @return the contents of the memory buffer as a String
	 */
	public String toString(String enc) throws UnsupportedEncodingException {
		return arr_.toString(enc);
	}

	public String inspect() {
		String buf = "";
		byte[] bytes = arr_.toByteArray();
		for (int i = 0; i < bytes.length; i++) {
			buf += (pos_ == i ? "==>" : "")
					+ Integer.toHexString(bytes[i] & 0xff) + " ";
		}
		return buf;
	}

	// The contents of the buffer
	private TByteArrayOutputStream arr_;

	// Position to read next byte from
	private int pos_;

	public int length() {
		return arr_.size();
	}

	public byte[] getArray() {
		return arr_.get();
	}
}

abstract class FunctionTransport extends TClearableMemoryBuffer {
	private TMemoryInputTransport returnBuffer;

	public FunctionTransport(TMemoryInputTransport inbytes) {
		super(100);
		returnBuffer = inbytes;
	}

	abstract protected byte[] apply(byte[] bytes);

	public void flush() throws TTransportException {
		super.flush();

		// Take our TMemoryBuffer buffer and make a copy of the contents
		byte toSend[] = Arrays.copyOf(getArray(), length());
		reset(); // Clear the buffer for next transaction
//		System.out.println("Sending event to client: "
//				+ Hex.encodeHexString(toSend));

		byte[] response = apply(toSend);

//		if (response!=null) {
//			System.out.println("Received response from client: "
//				+ Hex.encodeHexString(response));
//		}
//		else {
//			System.out.println("Received null response from client");
//		}
		returnBuffer.reset(response); // Set the input bytes that thrift will
										// parse to return response
	}

}