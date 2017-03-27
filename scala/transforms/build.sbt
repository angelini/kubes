name := "transforms"

version := "1.0"

scalaVersion := "2.12.1"

libraryDependencies ++= Seq(
  "org.apache.spark" % "spark-core_2.10" % "2.1.0"
)

mainClass in assembly := Some("com.alexangelini.kubes.transforms.VolumePerMonth")