package com.alexangelini

import java.util.Properties

import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}

import scala.io.Source

object Producer extends App {
  def readYahooFinanceFile(ticker: String) : Iterator[Array[String]] = {
    val file = Source.fromFile(s"/home/root/data/${ticker}_2015_2017.csv")
    file.getLines().drop(1).map(_.split(","))
  }

  def rowToJson(row: Array[String]) : String = {
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
  props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, s"${sys.env("KAFKA_SERVICE_SERVICE_HOST")}:${sys.env("KAFKA_SERVICE_SERVICE_PORT")}")
  // props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "192.168.64.4:32268")
  props.put(ProducerConfig.CLIENT_ID_CONFIG, "ScalaProducerExample")
  props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG , "org.apache.kafka.common.serialization.StringSerializer")
  props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer")

  val producer = new KafkaProducer[String, String](props)

  val records = readYahooFinanceFile("GOOG").map(rowToJson)
    .map(new ProducerRecord("sample_topic", "GOOG", _))

  println(s"started ${sys.env("KAFKA_SERVICE_SERVICE_HOST")}:${sys.env("KAFKA_SERVICE_SERVICE_PORT")}")

  for (record <- records) {
    producer.send(record)
    println(s"send ${record}")
  }

  println("done")
}
