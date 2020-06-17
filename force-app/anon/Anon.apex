System.Savepoint s = Database.setSavepoint();

System.debug('@@ call start '+Limits.getCpuTime());
Account a = new Account();
System.debug('@@ call end '+Limits.getCpuTime());

System.debug('@@ call start '+Limits.getCpuTime());
c_Log.send('message');
System.debug('@@ call end '+Limits.getCpuTime());

Database.rollback(s);