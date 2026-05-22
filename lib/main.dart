import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_filex/open_filex.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:flutter/services.dart' show rootBundle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vqudfifcvnyabltlpchq.supabase.co',
    anonKey: 'sb_publishable_wrpEuHLBa_uqHP7bPwSNLw_4JFf1vwc',
  );

  runApp(const JavneNabavkeApp());
}

class JavneNabavkeApp extends StatelessWidget {
  const JavneNabavkeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Javne Nabavke AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: 'Segoe UI'),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final imeController = TextEditingController();
  final prezimeController = TextEditingController();
  final emailController = TextEditingController();
  final lozinkaController = TextEditingController();

  PlatformFile? digitalniPotpis;
  bool loading = false;
  bool registracija = false;

  final supabase = Supabase.instance.client;

  Future<void> odaberiDigitalniPotpis() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['png', 'pdf'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        digitalniPotpis = result.files.first;
      });
    }
  }

  Future<String?> uploadPotpisa(String userId) async {
    if (digitalniPotpis == null || digitalniPotpis!.path == null) return null;

    final file = File(digitalniPotpis!.path!);
    final bytes = await file.readAsBytes();
    final ext = digitalniPotpis!.extension?.toLowerCase() ?? 'pdf';
    final safeName = digitalniPotpis!.name.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final filePath =
        '$userId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await supabase.storage
        .from('potpisi')
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: ext == 'png' ? 'image/png' : 'application/pdf',
          ),
        );

    return supabase.storage.from('potpisi').getPublicUrl(filePath);
  }

  Future<Map<String, dynamic>> ucitajProfil(String userId, String email) async {
    final response = await supabase
        .from('korisnici')
        .select()
        .eq('auth_user_id', userId)
        .maybeSingle();

    if (response == null) {
      return {
        'ime': 'Korisnik',
        'prezime': '',
        'email': email,
        'potpis_url': null,
      };
    }

    return Map<String, dynamic>.from(response);
  }

  Future<void> registrujKorisnika() async {
    if (imeController.text.trim().isEmpty ||
        prezimeController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        lozinkaController.text.trim().isEmpty ||
        digitalniPotpis == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Popuni ime, prezime, email, lozinku i učitaj digitalni potpis.',
          ),
        ),
      );
      return;
    }

    if (lozinkaController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lozinka mora imati najmanje 6 karaktera.'),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final authResponse = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: lozinkaController.text.trim(),
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('Registracija nije uspjela. Korisnik nije kreiran.');
      }

      final potpisUrl = await uploadPotpisa(user.id);

      final profil = {
        'auth_user_id': user.id,
        'ime': imeController.text.trim(),
        'prezime': prezimeController.text.trim(),
        'email': emailController.text.trim(),
        'potpis_url': potpisUrl,
      };

      await supabase.from('korisnici').insert(profil);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainScreen(userProfile: profil)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri registraciji: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> prijaviKorisnika() async {
    if (emailController.text.trim().isEmpty ||
        lozinkaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unesi email i lozinku.')));
      return;
    }

    setState(() => loading = true);

    try {
      final authResponse = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: lozinkaController.text.trim(),
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('Prijava nije uspjela.');
      }

      final profil = await ucitajProfil(
        user.id,
        user.email ?? emailController.text.trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainScreen(userProfile: profil)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri prijavi: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 25,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.gavel_rounded,
                  size: 58,
                  color: Color(0xFF102A43),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Javne Nabavke AI',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102A43),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  registracija ? 'Registracija korisnika' : 'Prijava korisnika',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 28),

                if (registracija) ...[
                  TextField(
                    controller: imeController,
                    decoration: InputDecoration(
                      labelText: 'Ime',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: prezimeController,
                    decoration: InputDecoration(
                      labelText: 'Prezime',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lozinkaController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Lozinka',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                if (registracija) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : odaberiDigitalniPotpis,
                      icon: const Icon(Icons.draw),
                      label: Text(
                        digitalniPotpis == null
                            ? 'Učitaj digitalni potpis PNG/PDF'
                            : digitalniPotpis!.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (digitalniPotpis != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Potpis učitan: ${digitalniPotpis!.name}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1F78B4),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: loading
                        ? null
                        : registracija
                        ? registrujKorisnika
                        : prijaviKorisnika,
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(registracija ? 'Registruj se' : 'Prijavi se'),
                  ),
                ),

                const SizedBox(height: 12),
                TextButton(
                  onPressed: loading
                      ? null
                      : () {
                          setState(() {
                            registracija = !registracija;
                          });
                        },
                  child: Text(
                    registracija
                        ? 'Već imaš nalog? Prijavi se'
                        : 'Nemaš nalog? Registruj se',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const MainScreen({super.key, required this.userProfile});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<String, dynamic>? korisnik;

  List<Map<String, dynamic>> registrovaniKorisnici = [];
  List<Map<String, dynamic>> javneNabavke = [];
  String? clanKomisije1;
  String? clanKomisije2;
  String? clanKomisije3;
  int selectedIndex = 0;
  List<bool> prikaziFormu = [false, false, false];
  List<PlatformFile> dokumenti = [];
  PlatformFile? dokumentZaPreview;
  bool prikaziPreview = false;
  final nazivController = TextEditingController();
  String organizacija = 'Društvo CK';
  final predmetController = TextEditingController();
  final vrijednostController = TextEditingController();
  final kriterijController = TextEditingController();

  String vrstaNabavke = 'Roba';

  final menuItems = [
    'Dashboard',
    'Javne nabavke',
    'Ponuđači',
    'Dokumenti',
    'AI analiza',
    'Izvještaji',
    'Podešavanja',
  ];

  final menuIcons = [
    Icons.dashboard,
    Icons.gavel,
    Icons.business,
    Icons.description,
    Icons.auto_awesome,
    Icons.picture_as_pdf,
    Icons.settings,
  ];

  @override
  void initState() {
    super.initState();
    korisnik = widget.userProfile;
    ucitajRegistrovaneKorisnike();
    ucitajJavneNabavke();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          sidebar(),
          Expanded(child: content()),
        ],
      ),
    );
  }

  Widget sidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF102A43),
      child: Column(
        children: [
          const SizedBox(height: 35),
          const Icon(Icons.gavel_rounded, size: 48, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            'Javne Nabavke AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 35),
          Expanded(
            child: ListView.builder(
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final selected = selectedIndex == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => selectedIndex = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF1F78B4)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(menuIcons[index], color: Colors.white, size: 21),
                          const SizedBox(width: 14),
                          Text(
                            menuItems[index],
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text('Verzija 0.2', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget content() {
    return Container(
      color: const Color(0xFFF4F7FA),
      padding: const EdgeInsets.all(30),

      child: Column(
        children: [
          /// GORNJI PROFIL BAR
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.red.shade100,
                    child: const Icon(Icons.person, color: Colors.red),
                  ),

                  const SizedBox(width: 12),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${korisnik?['ime'] ?? ''} ${korisnik?['prezime'] ?? ''}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),

                      Text(
                        korisnik?['email'] ?? '',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },

                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Odjava'),
              ),
            ],
          ),

          const SizedBox(height: 25),

          /// SADRŽAJ EKRANA
          Expanded(
            child: selectedIndex == 1
                ? javneNabavkeScreen()
                : selectedIndex == 2
                ? ponudjaciScreen()
                : selectedIndex == 3
                ? dokumentiScreen()
                : dashboardScreen(),
          ),
        ],
      ),
    );
  }

  Future<void> ucitajRegistrovaneKorisnike() async {
    final response = await Supabase.instance.client
        .from('korisnici')
        .select()
        .order('ime', ascending: true);

    if (!mounted) return;

    setState(() {
      registrovaniKorisnici = List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> ucitajJavneNabavke() async {
    final response = await Supabase.instance.client
        .from('javne_nabavke')
        .select()
        .order('created_at', ascending: false);

    if (!mounted) return;

    setState(() {
      javneNabavke = List<Map<String, dynamic>>.from(response);
    });
  }
String imeClanaKomisije(dynamic id) {
  if (id == null) return '';

  final korisnik = registrovaniKorisnici.firstWhere(
    (k) => k['auth_user_id'] == id,
    orElse: () => {},
  );

  return '${korisnik['ime'] ?? ''} ${korisnik['prezime'] ?? ''}'.trim();
}
Future<void> printajNabavku(Map<String, dynamic> nabavka) async {
  final pdf = pw.Document();

  final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
  final ttf = pw.Font.ttf(fontData);

  pdf.addPage(
    pw.Page(
      theme: pw.ThemeData.withFont(
        base: ttf,
        bold: ttf,
      ),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Javna nabavka',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              data: [
                ['Polje', 'Vrijednost'],
                ['Naziv', nabavka['naziv'] ?? ''],
                ['Organizacija', nabavka['organizacija'] ?? ''],
                ['Predmet', nabavka['predmet'] ?? ''],
                ['Vrsta nabavke', nabavka['vrsta_nabavke'] ?? ''],
                ['Procijenjena vrijednost', nabavka['procijenjena_vrijednost'] ?? ''],
                ['Kriterijum izbora', nabavka['kriterijum_izbora'] ?? ''],
                ['Član komisije 1', imeClanaKomisije(nabavka['clan_komisije_1'])],
                ['Član komisije 2', imeClanaKomisije(nabavka['clan_komisije_2'])],
                ['Član komisije 3', imeClanaKomisije(nabavka['clan_komisije_3'])],
                ['Datum kreiranja', nabavka['created_at'] ?? ''],
              ],
            ),
          ],
        );
      },
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => pdf.save(),
  );
}

Future<void> snimiNabavkuNaRacunar(Map<String, dynamic> nabavka) async {
  final izbor = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Izaberi format'),
        content: const Text('U kojem formatu želiš snimiti dokument?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'pdf'),
            child: const Text('PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'excel'),
            child: const Text('Excel'),
          ),
        ],
      );
    },
  );

  if (izbor == null) return;

  final nazivFajla = 'javna_nabavka_${nabavka['id']}';

  final putanja = await FilePicker.platform.saveFile(
    dialogTitle: 'Snimi javnu nabavku',
    fileName: izbor == 'pdf' ? '$nazivFajla.pdf' : '$nazivFajla.xlsx',
    type: FileType.custom,
    allowedExtensions: izbor == 'pdf' ? ['pdf'] : ['xlsx'],
  );

  if (putanja == null) return;
String finalPutanja = putanja;

if (izbor == 'pdf' &&
    !finalPutanja.toLowerCase().endsWith('.pdf')) {
  finalPutanja = '$finalPutanja.pdf';
}

if (izbor == 'excel' &&
    !finalPutanja.toLowerCase().endsWith('.xlsx')) {
  finalPutanja = '$finalPutanja.xlsx';
}
  if (izbor == 'pdf') {
    final pdf = pw.Document();
final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
final ttf = pw.Font.ttf(fontData);
    pdf.addPage(
      pw.Page(
  theme: pw.ThemeData.withFont(
    base: ttf,
    bold: ttf,
  ),
  build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Javna nabavka',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                data: [
                  ['Polje', 'Vrijednost'],
                  ['Naziv', nabavka['naziv'] ?? ''],
                  ['Organizacija', nabavka['organizacija'] ?? ''],
                  ['Predmet', nabavka['predmet'] ?? ''],
                  ['Vrsta nabavke', nabavka['vrsta_nabavke'] ?? ''],
                  [
                    'Procijenjena vrijednost',
                    nabavka['procijenjena_vrijednost'] ?? '',
                  ],
                  ['Kriterijum izbora', nabavka['kriterijum_izbora'] ?? ''],
                  [
                    'Član komisije 1',
                    imeClanaKomisije(nabavka['clan_komisije_1']),
                  ],
                  [
                    'Član komisije 2',
                    imeClanaKomisije(nabavka['clan_komisije_2']),
                  ],
                  [
                    'Član komisije 3',
                    imeClanaKomisije(nabavka['clan_komisije_3']),
                  ],
                  ['Datum kreiranja', nabavka['created_at'] ?? ''],
                ],
              ),
            ],
          );
        },
      ),
    );

    await File(finalPutanja).writeAsBytes(await pdf.save());
  } else {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    sheet.getRangeByName('A1').setText('Polje');
    sheet.getRangeByName('B1').setText('Vrijednost');

    final podaci = [
      ['Naziv', nabavka['naziv'] ?? ''],
      ['Organizacija', nabavka['organizacija'] ?? ''],
      ['Predmet', nabavka['predmet'] ?? ''],
      ['Vrsta nabavke', nabavka['vrsta_nabavke'] ?? ''],
      ['Procijenjena vrijednost', nabavka['procijenjena_vrijednost'] ?? ''],
      ['Kriterijum izbora', nabavka['kriterijum_izbora'] ?? ''],
      ['Član komisije 1', imeClanaKomisije(nabavka['clan_komisije_1'])],
      ['Član komisije 2', imeClanaKomisije(nabavka['clan_komisije_2'])],
      ['Član komisije 3', imeClanaKomisije(nabavka['clan_komisije_3'])],
      ['Datum kreiranja', nabavka['created_at'] ?? ''],
    ];

    for (int i = 0; i < podaci.length; i++) {
      sheet.getRangeByIndex(i + 2, 1).setText(podaci[i][0].toString());
      sheet.getRangeByIndex(i + 2, 2).setText(podaci[i][1].toString());
    }
final tabelaRange = sheet.getRangeByName('A1:B${podaci.length + 1}');
tabelaRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

sheet.getRangeByName('A1:B1').cellStyle.bold = true;
sheet.autoFitColumn(1);
sheet.autoFitColumn(2);
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    await File(finalPutanja).writeAsBytes(bytes);
  }

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Dokument je snimljen: $finalPutanja')),
  );
}
  Future<void> sacuvajJavnuNabavku() async {
    if (nazivController.text.trim().isEmpty ||
        predmetController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unesi najmanje naziv i predmet nabavke.'),
        ),
      );
      return;
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;

      await Supabase.instance.client.from('javne_nabavke').insert({
        'naziv': nazivController.text.trim(),
        'organizacija': organizacija,
        'predmet': predmetController.text.trim(),
        'vrsta_nabavke': vrstaNabavke,
        'procijenjena_vrijednost': vrijednostController.text.trim(),
        'kriterijum_izbora': kriterijController.text.trim(),
        'clan_komisije_1': clanKomisije1,
        'clan_komisije_2': clanKomisije2,
        'clan_komisije_3': clanKomisije3,
        'kreirao_korisnik': user?.id,
      });

      if (!mounted) return;

      nazivController.clear();
      predmetController.clear();
      vrijednostController.clear();
      kriterijController.clear();

      setState(() {
        organizacija = 'Društvo CK';
        vrstaNabavke = 'Roba';
        clanKomisije1 = null;
        clanKomisije2 = null;
        clanKomisije3 = null;
        selectedIndex = 0;
      });

      await ucitajJavneNabavke();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Javna nabavka je uspješno sačuvana u bazu.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Greška pri čuvanju nabavke: $e')),
      );
    }
  }
void prikaziNabavkuProzor(Map<String, dynamic> nabavka) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(nabavka['naziv'] ?? 'Javna nabavka'),
        content: SizedBox(
          width: 750,
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Polje')),
                DataColumn(label: Text('Vrijednost')),
              ],
              rows: [
                DataRow(cells: [
                  const DataCell(Text('Naziv')),
                  DataCell(Text(nabavka['naziv'] ?? '')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Organizacija')),
                  DataCell(Text(nabavka['organizacija'] ?? '')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Predmet')),
                  DataCell(Text(nabavka['predmet'] ?? '')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Vrsta nabavke')),
                  DataCell(Text(nabavka['vrsta_nabavke'] ?? '')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Procijenjena vrijednost')),
                  DataCell(Text(nabavka['procijenjena_vrijednost'] ?? '')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Kriterijum izbora')),
                  DataCell(Text(nabavka['kriterijum_izbora'] ?? '')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Član komisije 1')),
                  DataCell(Text(imeClanaKomisije(nabavka['clan_komisije_1']))),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Član komisije 2')),
                  DataCell(Text(imeClanaKomisije(nabavka['clan_komisije_2']))),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Član komisije 3')),
                  DataCell(Text(imeClanaKomisije(nabavka['clan_komisije_3']))),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Datum kreiranja')),
                  DataCell(Text(nabavka['created_at']?.toString() ?? '')),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await snimiNabavkuNaRacunar(nabavka);
            },
            icon: const Icon(Icons.save_alt),
            label: const Text('Snimi na računar'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await printajNabavku(nabavka);
            },
            icon: const Icon(Icons.print),
            label: const Text('Printaj'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.check),
            label: const Text('OK'),
          ),
        ],
      );
    },
  );
}

Widget dashboardScreen() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Dashboard'),
      const SizedBox(height: 8),
      const Text(
        'AI sistem za analizu ponuda i pripremu dokumentacije javnih nabavki.',
        style: TextStyle(fontSize: 16, color: Colors.black54),
      ),
      const SizedBox(height: 25),
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: boxDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Aktivne nabavke',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF102A43),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Osvježi listu',
                    onPressed: ucitajJavneNabavke,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Expanded(
                child: javneNabavke.isEmpty
                    ? const Text(
                        'Još nema sačuvanih javnih nabavki.',
                        style: TextStyle(color: Colors.black54),
                      )
                    : ListView.builder(
                        itemCount: javneNabavke.length,
                        itemBuilder: (context, index) {
                          final nabavka = javneNabavke[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                prikaziNabavkuProzor(nabavka);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4F7FA),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.link,
                                      color: Color(0xFF1F78B4),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        nabavka['naziv'] ?? '',
                                        style: const TextStyle(
                                          color: Color(0xFF1F78B4),
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.open_in_new,
                                      size: 18,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

  Future<void> ucitajNoviDokument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'jpg',
        'jpeg',
        'png',
      ],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        dokumentZaPreview = result.files.first;
        prikaziPreview = true;
      });
    }
  }

  Widget prikazPreviewa(PlatformFile doc) {
    final ext = doc.extension?.toLowerCase();

    if (doc.path == null) {
      return const Center(child: Text('Nije moguće prikazati dokument.'));
    }

    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(doc.path!),
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      );
    }

    if (ext == 'pdf') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SfPdfViewer.file(File(doc.path!)),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description, size: 80, color: Color(0xFF102A43)),
          const SizedBox(height: 15),
          Text(
            doc.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          const Text(
            'Word/Excel dokument se može otvoriti u programu na računaru.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),

          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: () {
              OpenFilex.open(doc.path!);
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Otvori dokument'),
          ),
        ],
      ),
    );
  }

  Widget dokumentiScreen() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title('Dokumenti'),
              const SizedBox(height: 8),
              const Text(
                'Učitavanje, pregled i potvrda dokumenata za postupak javne nabavke.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 25),

              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// LIJEVA STRANA
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: boxDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              onPressed: ucitajNoviDokument,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Učitaj novi dokument'),
                            ),

                            const SizedBox(height: 25),

                            const Text(
                              'Potvrđeni dokumenti',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF102A43),
                              ),
                            ),

                            const SizedBox(height: 12),

                            Expanded(
                              child: dokumenti.isEmpty
                                  ? const Text(
                                      'Još nema potvrđenih dokumenata.',
                                      style: TextStyle(color: Colors.black54),
                                    )
                                  : ListView.builder(
                                      itemCount: dokumenti.length,
                                      itemBuilder: (context, index) {
                                        final doc = dokumenti[index];

                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: () {
                                              setState(() {
                                                dokumentZaPreview = doc;
                                                prikaziPreview = true;
                                              });
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF4F7FA),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.link,
                                                    size: 18,
                                                    color: Color(0xFF1F78B4),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      doc.name,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF1F78B4,
                                                        ),
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 30),

                    /// DESNA STRANA - STVARNI PREVIEW
                    Expanded(
                      flex: 3,
                      child: prikaziPreview && dokumentZaPreview != null
                          ? Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.06),
                                          blurRadius: 14,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: prikazPreviewa(dokumentZaPreview!),
                                  ),
                                ),

                                const SizedBox(height: 15),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          prikaziPreview = false;
                                          dokumentZaPreview = null;
                                        });
                                      },
                                      icon: const Icon(Icons.close),
                                      label: const Text('Zatvori preview'),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          if (dokumentZaPreview != null &&
                                              !dokumenti.any(
                                                (doc) =>
                                                    doc.name ==
                                                        dokumentZaPreview!
                                                            .name &&
                                                    doc.path ==
                                                        dokumentZaPreview!.path,
                                              )) {
                                            dokumenti.add(dokumentZaPreview!);
                                          }

                                          prikaziPreview = false;
                                          dokumentZaPreview = null;
                                        });
                                      },
                                      icon: const Icon(Icons.check),
                                      label: const Text('Potvrdi'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Container(
                              width: double.infinity,
                              height: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: boxDecoration(),
                              child: const Center(
                                child: Text(
                                  'Učitaj dokument da bi se ovdje prikazao preview.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        /// FIKSNO DUGME DOLE DESNO
        Positioned(
          right: 0,
          bottom: 0,
          child: ElevatedButton.icon(
            onPressed: dokumenti.isEmpty
                ? null
                : () {
                    setState(() {
                      prikaziPreview = false;
                      dokumentZaPreview = null;
                      selectedIndex = 0;
                    });
                  },
            icon: const Icon(Icons.done_all),
            label: const Text('Gotovo'),
          ),
        ),
      ],
    );
  }

  Widget javneNabavkeScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('Nova javna nabavka'),
        const SizedBox(height: 8),
        const Text(
          'Unos osnovnih podataka o postupku javne nabavke.',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 25),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(25),
            decoration: boxDecoration(),
            child: ListView(
              children: [
                input('Naziv nabavke', nazivController),
                organizacijaDropdown(),
                input('Predmet nabavke', predmetController),
                dropdown(),
                input('Procijenjena vrijednost', vrijednostController),
                input('Kriterijum izbora', kriterijController),

                const SizedBox(height: 10),

                Row(
                  children: [
                    clanKomisijeDropdown(
                      label: 'Član komisije 1',
                      value: clanKomisije1,
                      onChanged: (value) {
                        setState(() {
                          clanKomisije1 = value;
                        });
                      },
                    ),

                    const SizedBox(width: 12),

                    clanKomisijeDropdown(
                      label: 'Član komisije 2',
                      value: clanKomisije2,
                      onChanged: (value) {
                        setState(() {
                          clanKomisije2 = value;
                        });
                      },
                    ),

                    const SizedBox(width: 12),

                    clanKomisijeDropdown(
                      label: 'Član komisije 3',
                      value: clanKomisije3,
                      onChanged: (value) {
                        setState(() {
                          clanKomisije3 = value;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: sacuvajJavnuNabavku,
                      icon: const Icon(Icons.save),
                      label: const Text('Sačuvaj nabavku'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        nazivController.clear();
                        predmetController.clear();
                        vrijednostController.clear();
                        kriterijController.clear();

                        setState(() {
                          clanKomisije1 = null;
                          clanKomisije2 = null;
                          clanKomisije3 = null;
                        });
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Očisti formu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget ponudjaciScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('Ponuđači'),

        const SizedBox(height: 8),

        const Text(
          'Unos i pregled ponuđača za postupak javne nabavke.',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),

        const SizedBox(height: 25),

        Expanded(
          child: Row(
            children: [
              ponudjacKartica(0, 'Ponuđač 1'),
              const SizedBox(width: 16),

              ponudjacKartica(1, 'Ponuđač 2'),
              const SizedBox(width: 16),

              ponudjacKartica(2, 'Ponuđač 3'),
            ],
          ),
        ),
      ],
    );
  }

  Widget ponudjacKartica(int index, String naslov) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: boxDecoration(),
        child: ListView(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  prikaziFormu[index] = true;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Dodaj ponuđača'),
            ),

            const SizedBox(height: 20),

            Center(child: Text(naslov, style: const TextStyle(fontSize: 22))),

            const SizedBox(height: 20),

            if (prikaziFormu[index]) ...[
              TextField(
                decoration: InputDecoration(
                  labelText: 'Naziv ponuđača',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                decoration: InputDecoration(
                  labelText: 'Adresa ponuđača',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                decoration: InputDecoration(
                  labelText: 'ID broj ponuđača',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                decoration: InputDecoration(
                  labelText: 'Broj bankovnog računa ponuđača',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kontakt osoba za ponudu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102A43),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Ime i prezime',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Br. tel',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Email',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextField(
                decoration: InputDecoration(
                  labelText: 'Datum dostavljene ponude',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: 'BAM',
                decoration: InputDecoration(
                  labelText: 'Valuta ponude',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: ['BAM', 'USD', 'EUR', 'CHF']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) {},
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.save),
                label: const Text('Spasi ponuđača'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget title(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: Color(0xFF102A43),
      ),
    );
  }

  Widget input(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget dropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: vrstaNabavke,
        decoration: InputDecoration(
          labelText: 'Vrsta nabavke',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          'Roba',
          'Usluga',
          'Radovi',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (value) {
          setState(() {
            vrstaNabavke = value!;
          });
        },
      ),
    );
  }

  Widget organizacijaDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: organizacija,
        decoration: InputDecoration(
          labelText: 'Organizacija',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          'Društvo CK',
          'CKRS',
          'CKFBIH',
          'CKBDBIH',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (value) {
          setState(() {
            organizacija = value!;
          });
        },
      ),
    );
  }

  Widget clanKomisijeDropdown({
    required String label,
    required String? value,
    required Function(String?) onChanged,
  }) {
    final zauzeti = [clanKomisije1, clanKomisije2, clanKomisije3];

    final dostupni = registrovaniKorisnici.where((korisnik) {
      final id = korisnik['auth_user_id'].toString();

      return value == id || !zauzeti.contains(id);
    }).toList();

    return Expanded(
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: dostupni.map((korisnik) {
          final id = korisnik['auth_user_id'].toString();

          final ime = korisnik['ime'] ?? '';
          final prezime = korisnik['prezime'] ?? '';

          return DropdownMenuItem<String>(
            value: id,
            child: Text('$ime $prezime'),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget card(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: boxDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFE3F2FD),
            child: Icon(icon, color: const Color(0xFF1F78B4)),
          ),
          const SizedBox(width: 18),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(title, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
