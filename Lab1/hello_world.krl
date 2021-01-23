ruleset hello_world {
  meta {
    name "Hello World"
    description <<
A first ruleset for the Quickstart
>>
    author "Phil Windley"
    shares hello
  }
   
  global {
    hello = function(obj) {
      msg = "Hello " + obj;
      msg
    }
  }
   
  rule hello_world {
    select when echo hello
    send_directive("say", {"something": "Hello World"})
  }

  rule monkey {
    select when echo monkey
    pre {
      // name = ("Hello " + event:attrs{"name"} || "Hello Monkey").klog("passed in name: ")
      name = (event:attrs{"name"} => "Hello " + event:attrs{"name"} | "Hello Monkey").klog("passed in name: ")
    }
    send_directive("say", {"something": name})
  }
   
}