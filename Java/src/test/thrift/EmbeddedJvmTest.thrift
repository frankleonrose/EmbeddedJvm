namespace java com.futurose.embeddedjvm

service TestHostToJvm {
  string echoString(1:string s)
  binary echoBinary(1:binary b)
  oneway void throwException()
}

service TestJvmToHost {
  string echoStringB(1:string s)
  binary echoBinaryB(1:binary b)
  oneway void throwExceptionB()
}
