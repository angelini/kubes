name := "producer"

version := "0.0.1"

scalaVersion := "2.12.1"

libraryDependencies ++= Seq(
  "org.apache.kafka" % "kafka_2.11" % "0.10.0.1"
)

mainClass in assembly := Some("com.alexangelini.kubes.producer.Producer")