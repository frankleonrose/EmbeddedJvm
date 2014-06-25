package com.futurose.embeddedjvm;

class TestClassWithNatives {
    public TestClassWithNatives() {
        method1();
        int value = method2("method2");
        Object obj = method3("method3", value);
    }
    
    native void method1();
    
    native int method2(String parameter);
    
    native Object method3(String parameter1, int parameter2);
}