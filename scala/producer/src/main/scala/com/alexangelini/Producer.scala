package com.alexangelini

import java.io.File
import java.util.Properties

import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
import org.apache.log4j.BasicConfigurator

import scala.io.Source

object Producer extends App {
  BasicConfigurator.configure()

  type Row = Array[String]

  def readYahooFinanceFile(f: File) : Iterator[(String, Row)] = {
    val ticker = f.getName().split("_")(0)
    Source.fromFile(f).getLines().drop(1).map(row => (ticker, row.split(",")))
  }

  def readYahooFinanceFiles() : Array[(String, Row)] = {
    val dir = new File("/home/root/data")
    // val dir = new File("/Users/alexangelini/src/kubes/data")
    dir.listFiles.filter(_.isFile)
      .flatMap(readYahooFinanceFile)
  }

  def rowToJson(row: Row) : String = {
    s"""{
      |  "date": "${row(0)}",
      |  "open": ${row(1).toDouble},
      |  "high": ${row(2).toDouble},
      |  "low": ${row(3).toDouble},
      |  "close": ${row(4).toDouble},
      |  "volume": ${row(5).toInt},
      |  "adj_close": ${row(6).toDouble}
      |}
    """.stripMargin
  }

  val props = new Properties()
  props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, s"${sys.env("KAFKA_SERVICE_HOST")}:${sys.env("KAFKA_SERVICE_PORT")}")
  // props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "192.168.64.4:30711")
  props.put(ProducerConfig.CLIENT_ID_CONFIG, "ScalaProducerExample")
  props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG , "org.apache.kafka.common.serialization.StringSerializer")
  props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer")

  val producer = new KafkaProducer[String, String](props)
  println(s"started ${sys.env("KAFKA_SERVICE_HOST")}:${sys.env("KAFKA_SERVICE_PORT")}")

  val records = readYahooFinanceFiles()
    .map({ case (ticker, row) => new ProducerRecord("sample_topic", ticker, rowToJson(row)) })

  for (record <- records) {
    producer.send(record)
    println(s"sent ${record}")
  }

  println("done")
}
