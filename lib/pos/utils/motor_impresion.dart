import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class MotorImpresion {
  static Future<Directory?> _obtenerDirectorioBase() async {
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory();
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  // =========================================================================
  // 🖨️ DISEÑO Y GENERACIÓN DEL TICKET DE VENTA (SAAS MULTI-TAMAÑO)
  // =========================================================================
  static Future<void> imprimirTicketVenta({
    required List<Map<String, dynamic>> carritoAEnviar,
    required String metodoDB,
    required double totalImpresion,
    required double pagoEf,
    required double pagoTr,
    required double cambioImpresion,
    required String descuentoTxt,
    required String vipTxt,
  }) async {
    final doc = pw.Document();
    pw.MemoryImage? imageLogo;

    // 🚨 1. CARGAMOS CONFIGURACIÓN SAAS DESDE MEMORIA
    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';
    final String mensajePersonalizado =
        prefs.getString('caja_mensaje_ticket') ??
        '¡Gracias por su preferencia!';
    final String nombreEmpresa =
        prefs.getString('caja_nombre_empresa') ?? 'TICKET DE VENTA';
    final String direccionEmpresa =
        prefs.getString('caja_direccion_empresa') ?? '';

    // Si el usuario configuró 58mm, lo usamos. Por defecto es 80mm.
    final double anchoImpresora =
        prefs.getDouble('caja_ancho_impresora') ?? 80.0;

    // 🚨 2. DESCARGAMOS EL LOGO DE LA EMPRESA
    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          imageLogo = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint('Aviso Logo SaaS: $e');
      }
    }

    final now = DateTime.now();
    final fechaHora =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // 🚨 3. ESCALADO INTELIGENTE (Si es de 58mm, reducimos la fuente para evitar cortes)
    double fBase = anchoImpresora == 58.0 ? 7.0 : 9.0;
    double fTitle = anchoImpresora == 58.0 ? 11.0 : 14.0;
    double fSmall = anchoImpresora == 58.0 ? 6.0 : 8.0;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          anchoImpresora * PdfPageFormat.mm,
          double.infinity,
          marginAll: 2 * PdfPageFormat.mm,
        ),
        build: (pw.Context pdfCtx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (imageLogo != null)
                pw.Image(
                  imageLogo,
                  width: anchoImpresora == 58.0 ? 45 : 65,
                  height: anchoImpresora == 58.0 ? 45 : 65,
                ),
              pw.SizedBox(height: 8),

              pw.Text(
                nombreEmpresa.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: fTitle,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),

              if (direccionEmpresa.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  direccionEmpresa,
                  style: pw.TextStyle(fontSize: fSmall),
                  textAlign: pw.TextAlign.center,
                ),
              ],

              pw.SizedBox(height: 6),
              pw.Text(fechaHora, style: pw.TextStyle(fontSize: fBase)),
              pw.Text(
                'Método: ${metodoDB == "MIXTO" ? "PAGO MIXTO" : metodoDB}',
                style: pw.TextStyle(
                  fontSize: fBase,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 4),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              ...carritoAEnviar.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item['cantidad']}x ${item['nombre']} [${item['talla']}]',
                          style: pw.TextStyle(fontSize: fBase),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        '\$${(item['precio'] * item['cantidad']).toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: fBase,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: 2),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              if (descuentoTxt.isNotEmpty) ...[
                pw.Text(descuentoTxt, style: pw.TextStyle(fontSize: fBase)),
                pw.SizedBox(height: 5),
              ],
              if (vipTxt.isNotEmpty) ...[
                pw.Text(
                  vipTxt,
                  style: pw.TextStyle(
                    fontSize: fBase,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
              ],

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${totalImpresion.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),

              if (metodoDB == "Efectivo") ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('EFECTIVO', style: pw.TextStyle(fontSize: fBase)),
                    pw.Text(
                      '\$${pagoEf.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CAMBIO', style: pw.TextStyle(fontSize: fBase)),
                    pw.Text(
                      '\$${cambioImpresion.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                  ],
                ),
              ] else if (metodoDB.startsWith("MIXTO")) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TRANSFERENCIA',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                    pw.Text(
                      '\$${pagoTr.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'EFECTIVO RECIBIDO',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                    pw.Text(
                      '\$${pagoEf.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'CAMBIO EN EFECTIVO',
                      style: pw.TextStyle(
                        fontSize: fBase,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '\$${cambioImpresion.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: fBase,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ] else if (metodoDB == "Transferencia") ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'PAGO APROBADO',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                    pw.Text(
                      'TRANSFERENCIA',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                  ],
                ),
              ] else ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'PAGO APROBADO',
                      style: pw.TextStyle(fontSize: fBase),
                    ),
                    pw.Text('TARJETA', style: pw.TextStyle(fontSize: fBase)),
                  ],
                ),
              ],

              pw.SizedBox(height: 10),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 10),

              // 🚨 MENSAJE FINAL DINÁMICO DE LA EMPRESA
              pw.Text(
                mensajePersonalizado,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: fSmall,
                  color: PdfColors.black,
                  lineSpacing: 1.5,
                ),
              ),

              pw.SizedBox(height: 15 * PdfPageFormat.mm),
            ],
          );
        },
      ),
    );

    try {
      final bytesPdf = await doc.save();
      final Directory? baseDir = await _obtenerDirectorioBase();
      if (baseDir != null) {
        final directorioTickets = Directory(
          '${baseDir.path}/Tickets_Guardados',
        );
        if (!await directorioTickets.exists()) {
          await directorioTickets.create(recursive: true);
        }
        final String nombreArchivo =
            'Ticket_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}.pdf';
        final File archivo = File('${directorioTickets.path}/$nombreArchivo');
        await archivo.writeAsBytes(bytesPdf);
      }
    } catch (e) {
      debugPrint('Aviso al guardar PDF local: $e');
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  // =========================================================================
  // 🖨️ DISEÑO Y GENERACIÓN DEL CORTE DE CAJA (SAAS MULTI-TAMAÑO)
  // =========================================================================
  static Future<void> imprimirCorteCaja({
    required int totalPiezas,
    required List<dynamic> detalles,
    required List<dynamic> apartados,
    required List<dynamic> cambios,
    required List<dynamic> gastosLista,
    required double calcVentasTotales,
    required double calcTarjeta,
    required double calcTransferencia,
    required double calcEfectivo,
    required double gastosTotales,
    required double totalFisicoCaja,
  }) async {
    final doc = pw.Document();
    pw.MemoryImage? imageLogo;

    // 🚨 1. CARGAMOS CONFIGURACIÓN SAAS
    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';
    final String nombreEmpresa =
        prefs.getString('caja_nombre_empresa') ?? 'MI NEGOCIO';
    final double anchoImpresora =
        prefs.getDouble('caja_ancho_impresora') ?? 80.0;

    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          imageLogo = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint('Aviso Logo SaaS: $e');
      }
    }

    final now = DateTime.now();
    final fechaHora =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    double fBase = anchoImpresora == 58.0 ? 7.0 : 9.0;
    double fTitle = anchoImpresora == 58.0 ? 11.0 : 14.0;
    double fSubtitle = anchoImpresora == 58.0 ? 8.0 : 10.0;
    double fSmall = anchoImpresora == 58.0 ? 6.0 : 8.0;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          anchoImpresora * PdfPageFormat.mm,
          double.infinity,
          marginAll: 2 * PdfPageFormat.mm,
        ),
        build: (pw.Context pdfCtx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (imageLogo != null)
                pw.Image(
                  imageLogo,
                  width: anchoImpresora == 58.0 ? 35 : 45,
                  height: anchoImpresora == 58.0 ? 35 : 45,
                ),
              pw.SizedBox(height: 5),
              pw.Text(
                'CORTE DE CAJA',
                style: pw.TextStyle(
                  fontSize: fTitle,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                nombreEmpresa.toUpperCase(),
                style: pw.TextStyle(fontSize: fSubtitle),
              ),
              pw.SizedBox(height: 5),
              pw.Text(fechaHora, style: pw.TextStyle(fontSize: fBase)),
              pw.Divider(),

              if (detalles.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'VENTAS DEL DÍA ($totalPiezas PZS)',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...detalles.map((item) {
                  String line = item['nombre'].toString();
                  String itemsVendidos = line.split('| Vendedor:')[0];
                  String vendedor = line.split('| Vendedor:').length > 1
                      ? line.split('| Vendedor:')[1]
                      : '';

                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        itemsVendidos.replaceAll('c/u.', 'c/u\n'),
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '${item['metodo'] ?? 'Efectivo'}',
                            style: pw.TextStyle(
                              fontSize: fBase,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            vendedor != '' ? 'Vend: $vendedor' : '',
                            style: pw.TextStyle(fontSize: fBase),
                          ),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            '\$${(item['precio'] as num).toDouble().toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: fSubtitle,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                    ],
                  );
                }),
                pw.Divider(),
              ],

              if (apartados.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'APARTADOS Y ABONOS',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...apartados.map(
                  (item) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item['tipo']} - ${item['cliente']}',
                          style: pw.TextStyle(fontSize: fBase),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        '\$${(item['monto'] as num).toDouble().toStringAsFixed(2)}',
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                    ],
                  ),
                ),
                pw.Divider(),
              ],

              if (cambios.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'CAMBIOS REALIZADOS',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...cambios.map(
                  (item) => pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Entró: ${item['entra']}',
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                      pw.Text(
                        'Salió: ${item['sale']}',
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                      pw.Text(
                        'Motivo: ${item['motivo']}',
                        style: pw.TextStyle(fontSize: fSmall),
                      ),
                      pw.SizedBox(height: 3),
                    ],
                  ),
                ),
                pw.Divider(),
              ],

              if (gastosLista.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'DETALLE DE GASTOS',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...gastosLista.map(
                  (item) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item['concepto']} (${item['hora'] ?? ''})',
                          style: pw.TextStyle(fontSize: fBase),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        '-\$${(item['monto'] as num).toDouble().toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: fBase,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.Text(
                'RESUMEN DE CAJA',
                style: pw.TextStyle(
                  fontSize: fTitle, // Un poco más destacado
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'PIEZAS VENDIDAS',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '$totalPiezas PZS',
                    style: pw.TextStyle(
                      fontSize: fSubtitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL EN TARJETA',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '\$${calcTarjeta.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                ],
              ),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL TRANSFERENCIA',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '\$${calcTransferencia.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL EN EFECTIVO',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '\$${calcEfectivo.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '- GASTOS DEL DÍA',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '-\$${gastosTotales.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                ],
              ),
              pw.Divider(),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'EFECTIVO A ENTREGAR',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${totalFisicoCaja.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL DE DINERO',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${calcVentasTotales.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 15 * PdfPageFormat.mm),
            ],
          );
        },
      ),
    );

    try {
      final bytesPdfCorte = await doc.save();
      final Directory? baseDir = await _obtenerDirectorioBase();
      if (baseDir != null) {
        final directorioCortes = Directory(
          '${baseDir.path}/Cortes_Caja_Guardados',
        );
        if (!await directorioCortes.exists()) {
          await directorioCortes.create(recursive: true);
        }
        final String nombreArchivo =
            'Corte_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';
        final File archivo = File('${directorioCortes.path}/$nombreArchivo');
        await archivo.writeAsBytes(bytesPdfCorte);
      }
    } catch (e) {
      debugPrint('Aviso al guardar PDF corte local: $e');
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Corte_Caja_$nombreEmpresa',
    );
  }
}
