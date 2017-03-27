package com.alexangelini.kubes.transforms

object VolumePerMonth extends App {
  val ds = spark.readStream.format("kafka").option("kafka.bootstrap.servers", s"${sys.env("KAFKA_SERVICE_HOST")}:${sys.env("KAFKA_SERVICE_PORT")}").option("subscribe", "sample_topic").load()
  val df = ds.selectExpr("CAST(key AS STRING)", "CAST(value AS STRING)").as[(String, String)]
  val query = df.writeStream.format("console").start()

  println("start")
}
