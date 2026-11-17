import 'package:aplicacion_flutter/utils/formateador_xml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('indenta estructura y conserva texto y entidades', () {
    expect(
      formatearXml(
        '<r><cliente>Ana &amp; Luis</cliente><total>57.50</total></r>',
      ),
      '<r>\n  <cliente>Ana &amp; Luis</cliente>\n  <total>57.50</total>\n</r>',
    );
  });
  test('conserva atributos con mayor que, CDATA, comentarios y etiquetas vacías', () {
    const xml =
        '<r><!--nota >--><dato limite="a > b"><![CDATA[<x>&texto]]></dato><vacio /></r>';
    expect(
      formatearXml(xml),
      '<r>\n  <!--nota >-->\n  <dato limite="a > b"><![CDATA[<x>&texto]]></dato>\n  <vacio />\n</r>',
    );
  });
  test('no agrega espacios en contenido mixto o con xml:space', () {
    for (final xml in [
      '<r>Hola <b>Ana</b>, bienvenida.</r>',
      '<r><p>Hola <b>Ana</b>.</p></r>',
      '<r xml:space="preserve"><a>  texto  </a><b /></r>',
      '<!DOCTYPE r [<!ENTITY saludo "Hola >">]><r>&saludo;</r>',
    ]) {
      expect(formatearXml(xml), xml);
    }
  });
  test('conserva espacios de valores y documentos truncados', () {
    expect(
      formatearXml('<r><a>  valor \n </a></r>'),
      '<r>\n  <a>  valor \n </a>\n</r>',
    );
    for (final xml in [
      '<r><a></r>',
      '<r atributo="sin cierre>',
      '<r><!--sin cierre',
    ]) {
      expect(formatearXml(xml), xml);
    }
  });
  test('formatear dos veces mantiene el mismo contenido', () {
    const xml = '<?xml version="1.0"?><r><a>1 &lt; 2</a><b /></r>';
    expect(formatearXml(formatearXml(xml)), formatearXml(xml));
  });
}
