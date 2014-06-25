package com.futurose.embeddedjvm;

import java.util.Arrays;

import org.apache.thrift.TException;
import org.apache.thrift.TProcessor;
import org.apache.thrift.protocol.TBinaryProtocol;
import org.apache.thrift.protocol.TProtocol;
import org.apache.thrift.transport.TMemoryBuffer;
import org.apache.thrift.transport.TMemoryInputTransport;

/**
 * A bidirectional synchronous communication channel between host and JVM code.
 * 
 * @param <TClient> The client class this channel knows how to build
 */
abstract public class ThriftChannel<TClient> {
	private long channel;
	private TProcessor processor;
	
	protected ThriftChannel() {
		this.channel = getChannel(this);
	}
	
	public void close() {
		synchronized(this) {
			if (channel!=0L) {
				long temp = channel;
				channel = 0L;
				releaseChannel(temp);
			}
		}
	}
	
	protected void finalize() {
		close();
	}
	
	/**
	 * Make an instance of the Thrift service processor implemented in JVM code.
	 * This processor is used when code in the host calls into the JVM.
	 * 
	 * <br/><br/><code>
	 * protected TProcessor makeProcessor() {<br/>
	 *  &nbsp;&nbsp;generated.HostToJvmApi.Iface impl = HostToJvmApiImplementation();<br/>
	 * 	&nbsp;&nbsp;return new generated.HostToJvmApi.Processor<generated.HostToJvmApi.Iface>(impl);<br/>
	 * }<br/>
	 * </code>
	 * @return An instance of a specific Thrift processor. May be null if this channel is used only to call host methods.
	 */
	abstract protected TProcessor makeProcessor();
	
	/**
	 * Make an instance of the Thrift service client used to call methods in the host.
	 * The type of the client is TClient, the type parameter of ThriftChannel. 
	 * 
	 * <br/><br/><code>
	 * protected generated.JvmToHostApi.Client makeClient(TProtocol in, TProtocol out) {<br/>
	 * &nbsp;&nbsp;return new generated.JvmToHostApi.Client(in, out);<br/>
	 * }<br/>
	 * @param in Protocol required for Client constructor
	 * @param out Protocol required for Client constructor
	 * @return An instance of the Client class. May be null if this channel is used only to call JVM methods.
	 */
	abstract protected TClient makeClient(TProtocol in, TProtocol out);
	
	protected TClient makeClient() {
		final TMemoryInputTransport inbytes = new TMemoryInputTransport();
		TBinaryProtocol input = new TBinaryProtocol(inbytes);
		final FunctionTransport outbytes = new FunctionTransport(inbytes) {
			@Override
			protected byte[] apply(byte[] bytes) {
				return callJvmToHost(channel, bytes);
			}
		};
		TBinaryProtocol output = new TBinaryProtocol(outbytes);
		
		return makeClient(input, output);
	}

	
	public byte[] callHostToJvm(byte[] bytes) throws Exception {
		try {
			if (processor==null) {
				// Create one and only one processor
				synchronized(this) {
					if (processor==null) {
						processor = makeProcessor();
					}
				}
			}

			// Wrap these bytes in a memory protocol and pass them to processor
			// System.out.println("JVM received bytes: " + Hex.encodeHexString(bytes));
			TMemoryInputTransport inbytes = new TMemoryInputTransport(bytes);
			TBinaryProtocol input = new TBinaryProtocol(inbytes);
			TMemoryBuffer outbytes = new TMemoryBuffer(100);
			TBinaryProtocol output = new TBinaryProtocol(outbytes);

			processor.process(input, output);

			byte toReturn[] = Arrays.copyOf(outbytes.getArray(),
					outbytes.length());
			// System.out.println("Engine returning bytes: " + Hex.encodeHexString(toReturn));
			return toReturn;
		} catch (TException e) {
			e.printStackTrace();
			throw e;
		}
	}

	native byte[] callJvmToHost(long channel, byte[] bytes);
	native long getChannel(Object counterpart);
	native void releaseChannel(long channel);
}