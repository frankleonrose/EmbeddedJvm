package com.futurose.embeddedjvm;

import java.nio.ByteBuffer;

import org.apache.thrift.TProcessor;
import org.apache.thrift.protocol.TProtocol;

import com.futurose.embeddedjvm.ThriftChannel;

class TestProcessor implements TestHostToJvm.Iface {
    public String echoString(String s) throws org.apache.thrift.TException {
        return s;
    }
    
    public ByteBuffer echoBinary(ByteBuffer b) throws org.apache.thrift.TException {
        return b;
    }
    
    public void throwException() throws org.apache.thrift.TException {
        throw new org.apache.thrift.TException("test exception");
    }
}

class TestThriftChannel extends ThriftChannel<TestJvmToHost.Client> {
	protected TProcessor makeProcessor() {
		return new TestHostToJvm.Processor<TestHostToJvm.Iface>(new TestProcessor());
	}
    
	protected TestJvmToHost.Client makeClient(TProtocol in, TProtocol out) {
		return new TestJvmToHost.Client(in, out);
	}
}