import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_filex/open_filex.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:http/http.dart' as http;

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
  bool prikaziLozinku = false;
  bool zapamtiLozinku = false;

  final supabase = Supabase.instance.client;
  @override
  void initState() {
    super.initState();
    ucitajZapamceniLogin();
  }

  Future<void> ucitajZapamceniLogin() async {
    final prefs = await SharedPreferences.getInstance();

    final email = prefs.getString('zadnji_email');
    final zapamti = prefs.getBool('zapamti_lozinku') ?? false;
    final lozinka = prefs.getString('zapamcena_lozinka');

    if (!mounted) return;

    setState(() {
      if (email != null) {
        emailController.text = email;
      }

      zapamtiLozinku = zapamti;

      if (zapamti && lozinka != null) {
        lozinkaController.text = lozinka;
      }
    });
  }

  Future<void> zapamtiLoginPodatke() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('zadnji_email', emailController.text.trim());
    await prefs.setBool('zapamti_lozinku', zapamtiLozinku);

    if (zapamtiLozinku) {
      await prefs.setString('zapamcena_lozinka', lozinkaController.text.trim());
    } else {
      await prefs.remove('zapamcena_lozinka');
    }
  }

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

      await zapamtiLoginPodatke();

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

      await zapamtiLoginPodatke();

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
                  color: Colors.black.withValues(alpha: 0.10),
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
                  obscureText: !prikaziLozinku,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    prijaviKorisnika();
                  },
                  decoration: InputDecoration(
                    labelText: 'Lozinka',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Prikaži password'),
                        value: prikaziLozinku,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setState(() {
                            prikaziLozinku = value ?? false;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Zapamti password'),
                        value: zapamtiLozinku,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setState(() {
                            zapamtiLozinku = value ?? false;
                          });
                        },
                      ),
                    ),
                  ],
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
  Map<String, dynamic>? odabranaNabavkaDashboard;
  List<Map<String, dynamic>> ponudjaciZaOdabranuNabavku = [];
  String? odabranaJavnaNabavkaZaPonudjace;
  String? clanKomisije1;
  String? clanKomisije2;
  String? clanKomisije3;
  int selectedIndex = 0;
  List<bool> prikaziFormu = [false, false, false];
  List<bool> ponudjacSacuvan = [false, false, false];
  final ponudjacNazivControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacAdresaControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacIdBrojControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacRacunControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacKontaktControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacTelefonControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacEmailControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacDatumControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final ponudjacValuta = ['BAM', 'BAM', 'BAM'];

  String? odabranaJavnaNabavkaZaDokumente;
  List<Map<String, dynamic>> ponudjaciZaDokumente = [];
  final List<PlatformFile?> dokumentiPonudjaca = [null, null, null];
  final List<Map<String, dynamic>?> dokumentiPonudjacaInfo = [null, null, null];

  List<PlatformFile> dokumenti = [];
  PlatformFile? dokumentZaPreview;
  bool prikaziPreview = false;
  final nazivController = TextEditingController();
  final projekatController = TextEditingController();
  final donatorController = TextEditingController();
  final osnovPokretanjaController = TextEditingController();
  final vrijemePokretanjaController = TextEditingController();
  String program = 'Migracije';

  final programi = [
    'Migracije',
    'Priprema i odgovor na katastrofe',
    'Služba traženja',
    'Međunarodna saradnja',
    'Socijalno humanitarna djelatnost',
    'Namicanje sredstava',
    'Mine',
    'Mladi',
    'Diseminacija',
    'Finansije',
    'Zdravstvo',
  ];
  String organizacija = 'Društvo CK';
  final predmetController = TextEditingController();
  final vrijednostController = TextEditingController();
  final kriterijController = TextEditingController();
  final vrijemePokretanjaMask = MaskTextInputFormatter(
    mask: '##:## ##.##.####',
    filter: {"#": RegExp(r'[0-9]')},
  );

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
                : selectedIndex == 4
                ? aiAnalizaScreen()
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

  List<List<String>> podaciNabavkeZaTabelu(
    Map<String, dynamic> nabavka,
    List<Map<String, dynamic>> ponudjaciZaPopup,
  ) {
    final podaci = <List<String>>[
      ['Polje', 'Vrijednost'],
      ['Program', nabavka['program']?.toString() ?? ''],
      ['Projekat', nabavka['projekat']?.toString() ?? ''],
      ['Donator', nabavka['donator']?.toString() ?? ''],
      [
        'Osnov za pokretanje nabavke',
        nabavka['osnov_pokretanja']?.toString() ?? '',
      ],
      [
        'Vrijeme pokretanja nabavke',
        nabavka['vrijeme_pokretanja']?.toString() ?? '',
      ],
      ['Naziv', nabavka['naziv']?.toString() ?? ''],
      ['Organizacija', nabavka['organizacija']?.toString() ?? ''],
      ['Predmet', nabavka['predmet']?.toString() ?? ''],
      ['Vrsta nabavke', nabavka['vrsta_nabavke']?.toString() ?? ''],
      [
        'Procijenjena vrijednost',
        nabavka['procijenjena_vrijednost']?.toString() ?? '',
      ],
      ['Kriterijum izbora', nabavka['kriterijum_izbora']?.toString() ?? ''],
      ['Član komisije 1', imeClanaKomisije(nabavka['clan_komisije_1'])],
      ['Član komisije 2', imeClanaKomisije(nabavka['clan_komisije_2'])],
      ['Član komisije 3', imeClanaKomisije(nabavka['clan_komisije_3'])],
      ['Datum kreiranja', nabavka['created_at']?.toString() ?? ''],
    ];

    if (ponudjaciZaPopup.isEmpty) {
      podaci.add([
        'Ponuđači',
        'Još nema unesenih ponuđača za ovu javnu nabavku.',
      ]);
    } else {
      for (final ponuda in ponudjaciZaPopup) {
        final ponudjacRaw = ponuda['ponudjaci'];
        final ponudjac = ponudjacRaw is Map
            ? Map<String, dynamic>.from(ponudjacRaw)
            : <String, dynamic>{};

        podaci.add([
          'Ponuđač ${ponuda['redni_broj'] ?? ''}',
          ponudjac['naziv']?.toString() ?? '',
        ]);
      }
    }

    return podaci;
  }

  Future<void> printajNabavku(
    Map<String, dynamic> nabavka, [
    List<Map<String, dynamic>> ponudjaciZaPopup = const [],
  ]) async {
    final pdf = pw.Document();

    final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final ttf = pw.Font.ttf(fontData);

    final podaci = podaciNabavkeZaTabelu(nabavka, ponudjaciZaPopup);

    pdf.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
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
              pw.TableHelper.fromTextArray(data: podaci),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<void> snimiNabavkuNaRacunar(
    Map<String, dynamic> nabavka, [
    List<Map<String, dynamic>> ponudjaciZaPopup = const [],
  ]) async {
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

    if (izbor == 'pdf' && !finalPutanja.toLowerCase().endsWith('.pdf')) {
      finalPutanja = '$finalPutanja.pdf';
    }

    if (izbor == 'excel' && !finalPutanja.toLowerCase().endsWith('.xlsx')) {
      finalPutanja = '$finalPutanja.xlsx';
    }

    final podaci = podaciNabavkeZaTabelu(nabavka, ponudjaciZaPopup);

    if (izbor == 'pdf') {
      final pdf = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
      final ttf = pw.Font.ttf(fontData);

      pdf.addPage(
        pw.Page(
          theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
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
                pw.TableHelper.fromTextArray(data: podaci),
              ],
            );
          },
        ),
      );

      await File(finalPutanja).writeAsBytes(await pdf.save());
    } else {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];

      sheet.name = 'Javna nabavka';

      for (int i = 0; i < podaci.length; i++) {
        sheet.getRangeByIndex(i + 1, 1).setText(podaci[i][0]);
        sheet.getRangeByIndex(i + 1, 2).setText(podaci[i][1]);
      }

      final tabelaRange = sheet.getRangeByName('A1:B${podaci.length}');
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
        'program': program,
        'naziv': nazivController.text.trim(),
        'organizacija': organizacija,
        'projekat': projekatController.text.trim(),
        'donator': donatorController.text.trim(),
        'osnov_pokretanja': osnovPokretanjaController.text.trim(),
        'vrijeme_pokretanja': vrijemePokretanjaController.text.trim(),
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
      projekatController.clear();
      donatorController.clear();
      osnovPokretanjaController.clear();
      vrijemePokretanjaController.clear();

      setState(() {
        program = 'Migracije';
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri čuvanju nabavke: $e')));
    }
  }

  Future<void> sacuvajPonudjaca(int index) async {
    if (odabranaJavnaNabavkaZaPonudjace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prvo izaberi javnu nabavku.')),
      );
      return;
    }

    final naziv = ponudjacNazivControllers[index].text.trim();
    final idBroj = ponudjacIdBrojControllers[index].text.trim();

    if (naziv.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unesi naziv ponuđača.')));
      return;
    }

    try {
      Map<String, dynamic>? postojeciPonudjac;

      if (idBroj.isNotEmpty) {
        postojeciPonudjac = await Supabase.instance.client
            .from('ponudjaci')
            .select()
            .eq('id_broj', idBroj)
            .maybeSingle();
      }

      postojeciPonudjac ??= await Supabase.instance.client
          .from('ponudjaci')
          .select()
          .eq('naziv', naziv)
          .maybeSingle();

      String ponudjacId;

      if (postojeciPonudjac == null) {
        final noviPonudjac = await Supabase.instance.client
            .from('ponudjaci')
            .insert({
              'naziv': naziv,
              'adresa': ponudjacAdresaControllers[index].text.trim(),
              'id_broj': idBroj,
              'bankovni_racun': ponudjacRacunControllers[index].text.trim(),
              'kontakt_osoba': ponudjacKontaktControllers[index].text.trim(),
              'telefon': ponudjacTelefonControllers[index].text.trim(),
              'email': ponudjacEmailControllers[index].text.trim(),
            })
            .select()
            .single();

        ponudjacId = noviPonudjac['id'].toString();
      } else {
        ponudjacId = postojeciPonudjac['id'].toString();
      }

      await Supabase.instance.client.from('ponude').insert({
        'javna_nabavka_id': odabranaJavnaNabavkaZaPonudjace,
        'ponudjac_id': ponudjacId,
        'redni_broj': index + 1,
        'datum_dostavljene_ponude': ponudjacDatumControllers[index].text.trim(),
        'valuta': ponudjacValuta[index],
      });

      ponudjacNazivControllers[index].clear();
      ponudjacAdresaControllers[index].clear();
      ponudjacIdBrojControllers[index].clear();
      ponudjacRacunControllers[index].clear();
      ponudjacKontaktControllers[index].clear();
      ponudjacTelefonControllers[index].clear();
      ponudjacEmailControllers[index].clear();
      ponudjacDatumControllers[index].clear();

      setState(() {
        ponudjacSacuvan[index] = true;
      });

      if (odabranaNabavkaDashboard?['id']?.toString() ==
          odabranaJavnaNabavkaZaPonudjace) {
        await ucitajPonudjaceZaNabavku(odabranaJavnaNabavkaZaPonudjace!);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ponuđač je uspješno povezan sa nabavkom.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Greška pri čuvanju ponuđača: $e')),
      );
    }
  }

  Future<void> ucitajPonudjaceZaNabavku(String javnaNabavkaId) async {
    final response = await Supabase.instance.client
        .from('ponude')
        .select('''
        id,
        redni_broj,
        datum_dostavljene_ponude,
        valuta,
        ponudjaci (
          id,
          naziv,
          adresa,
          id_broj,
          bankovni_racun,
          kontakt_osoba,
          telefon,
          email
        )
      ''')
        .eq('javna_nabavka_id', javnaNabavkaId)
        .order('redni_broj', ascending: true);

    if (!mounted) return;

    setState(() {
      ponudjaciZaOdabranuNabavku = List<Map<String, dynamic>>.from(response);
    });
  }

  List<List<String>> podaciPonudjacaZaTabelu(Map<String, dynamic> ponuda) {
    final ponudjacRaw = ponuda['ponudjaci'];
    final ponudjac = ponudjacRaw is Map
        ? Map<String, dynamic>.from(ponudjacRaw)
        : <String, dynamic>{};

    return [
      ['Polje', 'Vrijednost'],
      ['Javna nabavka', odabranaNabavkaDashboard?['naziv']?.toString() ?? ''],
      ['Redni broj', ponuda['redni_broj']?.toString() ?? ''],
      ['Naziv ponuđača', ponudjac['naziv']?.toString() ?? ''],
      ['Adresa', ponudjac['adresa']?.toString() ?? ''],
      ['ID broj', ponudjac['id_broj']?.toString() ?? ''],
      ['Bankovni račun', ponudjac['bankovni_racun']?.toString() ?? ''],
      ['Kontakt osoba', ponudjac['kontakt_osoba']?.toString() ?? ''],
      ['Telefon', ponudjac['telefon']?.toString() ?? ''],
      ['Email', ponudjac['email']?.toString() ?? ''],
      [
        'Datum dostavljene ponude',
        ponuda['datum_dostavljene_ponude']?.toString() ?? '',
      ],
      ['Valuta', ponuda['valuta']?.toString() ?? ''],
    ];
  }

  Future<void> printajPonudjaca(Map<String, dynamic> ponuda) async {
    final pdf = pw.Document();

    final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final ttf = pw.Font.ttf(fontData);

    pdf.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Podaci o ponuđaču',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                data: podaciPonudjacaZaTabelu(ponuda),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<void> snimiPonudjacaNaRacunar(Map<String, dynamic> ponuda) async {
    final ponudjacRaw = ponuda['ponudjaci'];
    final ponudjac = ponudjacRaw is Map
        ? Map<String, dynamic>.from(ponudjacRaw)
        : <String, dynamic>{};

    final izbor = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Izaberi format'),
          content: const Text(
            'U kojem formatu želiš snimiti podatke o ponuđaču?',
          ),
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

    final safeNaziv = (ponudjac['naziv']?.toString() ?? 'ponudjac')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_ -]'), '_')
        .replaceAll(' ', '_');

    final putanja = await FilePicker.platform.saveFile(
      dialogTitle: 'Snimi podatke o ponuđaču',
      fileName: izbor == 'pdf' ? '$safeNaziv.pdf' : '$safeNaziv.xlsx',
      type: FileType.custom,
      allowedExtensions: izbor == 'pdf' ? ['pdf'] : ['xlsx'],
    );

    if (putanja == null) return;

    String finalPutanja = putanja;

    if (izbor == 'pdf' && !finalPutanja.toLowerCase().endsWith('.pdf')) {
      finalPutanja = '$finalPutanja.pdf';
    }

    if (izbor == 'excel' && !finalPutanja.toLowerCase().endsWith('.xlsx')) {
      finalPutanja = '$finalPutanja.xlsx';
    }

    final podaci = podaciPonudjacaZaTabelu(ponuda);

    if (izbor == 'pdf') {
      final pdf = pw.Document();

      final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
      final ttf = pw.Font.ttf(fontData);

      pdf.addPage(
        pw.Page(
          theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Podaci o ponuđaču',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(data: podaci),
              ],
            );
          },
        ),
      );

      await File(finalPutanja).writeAsBytes(await pdf.save());
    } else {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];

      sheet.name = 'Ponuđač';

      for (int i = 0; i < podaci.length; i++) {
        sheet.getRangeByIndex(i + 1, 1).setText(podaci[i][0]);
        sheet.getRangeByIndex(i + 1, 2).setText(podaci[i][1]);
      }

      final tabelaRange = sheet.getRangeByName('A1:B${podaci.length}');
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

  void prikaziPonudjacaProzor(Map<String, dynamic> ponuda) {
    final ponudjacRaw = ponuda['ponudjaci'];
    final ponudjac = ponudjacRaw is Map
        ? Map<String, dynamic>.from(ponudjacRaw)
        : <String, dynamic>{};

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(ponudjac['naziv']?.toString() ?? 'Ponuđač'),
          content: SizedBox(
            width: 750,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Polje')),
                  DataColumn(label: Text('Vrijednost')),
                ],
                rows: [
                  DataRow(
                    cells: [
                      const DataCell(Text('Javna nabavka')),
                      DataCell(
                        Text(
                          odabranaNabavkaDashboard?['naziv']?.toString() ?? '',
                        ),
                      ),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Redni broj')),
                      DataCell(Text(ponuda['redni_broj']?.toString() ?? '')),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Naziv ponuđača')),
                      DataCell(Text(ponudjac['naziv']?.toString() ?? '')),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Adresa')),
                      DataCell(Text(ponudjac['adresa']?.toString() ?? '')),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('ID broj')),
                      DataCell(Text(ponudjac['id_broj']?.toString() ?? '')),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Bankovni račun')),
                      DataCell(
                        Text(ponudjac['bankovni_racun']?.toString() ?? ''),
                      ),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Kontakt osoba')),
                      DataCell(
                        Text(ponudjac['kontakt_osoba']?.toString() ?? ''),
                      ),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Telefon')),
                      DataCell(Text(ponudjac['telefon']?.toString() ?? '')),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Email')),
                      DataCell(Text(ponudjac['email']?.toString() ?? '')),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Datum dostavljene ponude')),
                      DataCell(
                        Text(
                          ponuda['datum_dostavljene_ponude']?.toString() ?? '',
                        ),
                      ),
                    ],
                  ),
                  DataRow(
                    cells: [
                      const DataCell(Text('Valuta')),
                      DataCell(Text(ponuda['valuta']?.toString() ?? '')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await snimiPonudjacaNaRacunar(ponuda);
              },
              icon: const Icon(Icons.save_alt),
              label: const Text('Snimi na računar'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await printajPonudjaca(ponuda);
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

  Future<void> prikaziNabavkuProzor(Map<String, dynamic> nabavka) async {
    List<Map<String, dynamic>> ponudjaciZaPopup = [];

    try {
      final response = await Supabase.instance.client
          .from('ponude')
          .select('''
          id,
          redni_broj,
          datum_dostavljene_ponude,
          valuta,
          ponudjaci (
            id,
            naziv,
            adresa,
            id_broj,
            bankovni_racun,
            kontakt_osoba,
            telefon,
            email
          )
        ''')
          .eq('javna_nabavka_id', nabavka['id'].toString())
          .order('redni_broj', ascending: true);

      ponudjaciZaPopup = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Greška pri učitavanju ponuđača: $e')),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final rows = <DataRow>[
          DataRow(
            cells: [
              const DataCell(Text('Program')),
              DataCell(Text(nabavka['program']?.toString() ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Projekat')),
              DataCell(Text(nabavka['projekat']?.toString() ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Donator')),
              DataCell(Text(nabavka['donator']?.toString() ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Osnov za pokretanje nabavke')),
              DataCell(Text(nabavka['osnov_pokretanja']?.toString() ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Vrijeme pokretanja nabavke')),
              DataCell(Text(nabavka['vrijeme_pokretanja']?.toString() ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Naziv')),
              DataCell(Text(nabavka['naziv'] ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Organizacija')),
              DataCell(Text(nabavka['organizacija'] ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Predmet')),
              DataCell(Text(nabavka['predmet'] ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Vrsta nabavke')),
              DataCell(Text(nabavka['vrsta_nabavke'] ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Procijenjena vrijednost')),
              DataCell(Text(nabavka['procijenjena_vrijednost'] ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Kriterijum izbora')),
              DataCell(Text(nabavka['kriterijum_izbora'] ?? '')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Član komisije 1')),
              DataCell(Text(imeClanaKomisije(nabavka['clan_komisije_1']))),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Član komisije 2')),
              DataCell(Text(imeClanaKomisije(nabavka['clan_komisije_2']))),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Član komisije 3')),
              DataCell(Text(imeClanaKomisije(nabavka['clan_komisije_3']))),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Datum kreiranja')),
              DataCell(Text(nabavka['created_at']?.toString() ?? '')),
            ],
          ),
          const DataRow(
            cells: [
              DataCell(
                Text(
                  'Ponuđači vezani za ovu javnu nabavku',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(Text('')),
            ],
          ),
        ];

        if (ponudjaciZaPopup.isEmpty) {
          rows.add(
            const DataRow(
              cells: [
                DataCell(Text('Ponuđači')),
                DataCell(
                  Text('Još nema unesenih ponuđača za ovu javnu nabavku.'),
                ),
              ],
            ),
          );
        } else {
          for (final ponuda in ponudjaciZaPopup) {
            final ponudjacRaw = ponuda['ponudjaci'];
            final ponudjac = ponudjacRaw is Map
                ? Map<String, dynamic>.from(ponudjacRaw)
                : <String, dynamic>{};

            rows.add(
              DataRow(
                cells: [
                  DataCell(Text('Ponuđač ${ponuda['redni_broj'] ?? ''}')),
                  DataCell(Text(ponudjac['naziv']?.toString() ?? '')),
                ],
              ),
            );
          }
        }

        return AlertDialog(
          title: Text(nabavka['naziv'] ?? 'Javna nabavka'),
          content: SizedBox(
            width: 900,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Polje')),
                  DataColumn(label: Text('Vrijednost')),
                ],
                rows: rows,
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await snimiNabavkuNaRacunar(nabavka, ponudjaciZaPopup);
              },
              icon: const Icon(Icons.save_alt),
              label: const Text('Snimi na računar'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await printajNabavku(nabavka, ponudjaciZaPopup);
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

  bool aiAnalizaLoading = false;
  String? odabranaJavnaNabavkaZaAi;
  Map<String, dynamic>? rezultatAiAnalize;
  List<Map<String, dynamic>> get aiAnalizeLista {
    final analiza = rezultatAiAnalize?['analiza'];

    if (analiza is List) {
      return analiza
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }

  Future<bool> ucitajPostojeceAiAnalize() async {
    if (odabranaJavnaNabavkaZaAi == null) return false;

    final response = await Supabase.instance.client
        .from('ai_analize')
        .select()
        .eq('javna_nabavka_id', odabranaJavnaNabavkaZaAi!)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response);

    if (rows.isEmpty) return false;

    final analiza = rows.map((row) {
      final greska = row['greska'];
      final aiJson = row['ai_json'];

      return <String, dynamic>{
        'dokument': row['naziv_fajla']?.toString() ?? 'Dokument bez naziva',
        'ai_json': aiJson,
        if (greska != null && greska.toString().trim().isNotEmpty)
          'greska': greska.toString(),
      };
    }).toList();

    if (!mounted) return true;

    setState(() {
      rezultatAiAnalize = {
        'success': true,
        'broj_pdf_dokumenata': analiza.length,
        'analiza': analiza,
        'iz_baze': true,
      };
    });

    return true;
  }

  Future<void> pokreniAiAnalizu({bool forsirajNovuAnalizu = false}) async {
    if (odabranaJavnaNabavkaZaAi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prvo izaberi javnu nabavku.')),
      );
      return;
    }

    setState(() => aiAnalizaLoading = true);

    try {
      if (!forsirajNovuAnalizu) {
        final imaPostojecaAnaliza = await ucitajPostojeceAiAnalize();

        if (imaPostojecaAnaliza) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Prikazana je već sačuvana AI analiza iz baze.'),
            ),
          );

          return;
        }
      }

      final response = await Supabase.instance.client.functions.invoke(
        'ai_analiza',
        body: {'javna_nabavka_id': odabranaJavnaNabavkaZaAi},
      );

      if (!mounted) return;

      setState(() {
        rezultatAiAnalize = Map<String, dynamic>.from(response.data);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.data['message']?.toString() ?? 'AI backend je odgovorio.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška AI analize: $e')));
    } finally {
      if (mounted) {
        setState(() => aiAnalizaLoading = false);
      }
    }
  }

  Widget _aiInfoChip(String label, dynamic value) {
    final text = value?.toString().trim().isNotEmpty == true
        ? value.toString()
        : 'nije navedeno';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF102A43),
            ),
          ),
        ],
      ),
    );
  }

  Widget aiAnalizaScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('AI analiza ponuda'),
        const SizedBox(height: 8),
        const Text(
          'AI čita PDF ponude ponuđača i priprema KAP analizu.',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 20),

        DropdownButtonFormField<String>(
          initialValue: odabranaJavnaNabavkaZaAi,
          decoration: InputDecoration(
            labelText: 'Izaberi javnu nabavku',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: javneNabavke.map((nabavka) {
            return DropdownMenuItem<String>(
              value: nabavka['id'].toString(),
              child: Text(nabavka['naziv'] ?? 'Bez naziva'),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              odabranaJavnaNabavkaZaAi = value;
              rezultatAiAnalize = null;
            });
          },
        ),

        const SizedBox(height: 20),

        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: aiAnalizaLoading
                  ? null
                  : () => pokreniAiAnalizu(forsirajNovuAnalizu: false),
              icon: const Icon(Icons.visibility),
              label: Text(
                aiAnalizaLoading ? 'Učitavam...' : 'Prikaži AI analizu',
              ),
            ),
            OutlinedButton.icon(
              onPressed: aiAnalizaLoading
                  ? null
                  : () => pokreniAiAnalizu(forsirajNovuAnalizu: true),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Pokreni novu AI analizu'),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (rezultatAiAnalize != null &&
            rezultatAiAnalize?['iz_baze'] == true) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Text(
              'Prikazani su već sačuvani rezultati iz baze. Za novu obradu klikni „Pokreni novu AI analizu”.',
              style: TextStyle(color: Color(0xFF1B5E20)),
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (rezultatAiAnalize != null)
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: boxDecoration(),
              child: aiAnalizeLista.isEmpty
                  ? const Center(
                      child: Text(
                        'Nema rezultata AI analize za prikaz.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: aiAnalizeLista.length,
                      itemBuilder: (context, index) {
                        final dokument = aiAnalizeLista[index];
                        final rawAiJson = dokument['ai_json'];
                        final aiJson = rawAiJson is Map
                            ? Map<String, dynamic>.from(rawAiJson)
                            : null;
                        final rawStavke = aiJson?['stavke'];
                        final stavke = rawStavke is List ? rawStavke : [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.description,
                                      color: Color(0xFF1F78B4),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        dokument['dokument']?.toString() ??
                                            'Dokument bez naziva',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF102A43),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (dokument['greska'] != null)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      'Greška: ${dokument['greska']}',
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                if (aiJson != null) ...[
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _aiInfoChip(
                                        'Ponuđač',
                                        aiJson['naziv_ponudjaca'],
                                      ),
                                      _aiInfoChip(
                                        'Ukupna cijena',
                                        aiJson['ukupna_cijena'],
                                      ),
                                      _aiInfoChip('PDV', aiJson['pdv']),
                                      _aiInfoChip(
                                        'Rok isporuke',
                                        aiJson['rok_isporuke'],
                                      ),
                                      _aiInfoChip(
                                        'Garancija',
                                        aiJson['garancija'],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if ((aiJson['opis_ponude'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      'Opis: ${aiJson['opis_ponude']}',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Stavke:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF102A43),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (stavke.isEmpty)
                                    const Text(
                                      'Nema pronađenih stavki.',
                                      style: TextStyle(color: Colors.black54),
                                    )
                                  else
                                    ...stavke.map((stavkaRaw) {
                                      final stavka = stavkaRaw is Map
                                          ? Map<String, dynamic>.from(stavkaRaw)
                                          : <String, dynamic>{};

                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF4F7FA),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          '• ${stavka['naziv_stavke'] ?? 'nije navedeno'} | '
                                          '${stavka['kolicina'] ?? 'nije navedeno'} | '
                                          '${stavka['jedinicna_cijena'] ?? 'nije navedeno'} | '
                                          '${stavka['ukupno'] ?? 'nije navedeno'}',
                                        ),
                                      );
                                    }),
                                  if ((aiJson['napomena'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Napomena: ${aiJson['napomena']}',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
      ],
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
          child: Row(
            children: [
              Expanded(
                flex: 2,
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
                                  final selected =
                                      odabranaNabavkaDashboard?['id'] ==
                                      nabavka['id'];

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () async {
                                        setState(() {
                                          odabranaNabavkaDashboard = nabavka;
                                          ponudjaciZaOdabranuNabavku = [];
                                        });

                                        await ucitajPonudjaceZaNabavku(
                                          nabavka['id'].toString(),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? const Color(0xFFE3F2FD)
                                              : const Color(0xFFF4F7FA),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? const Color(0xFF1F78B4)
                                                : Colors.grey.shade300,
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
                                                  decoration:
                                                      TextDecoration.underline,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Detalji javne nabavke',
                                              onPressed: () {
                                                prikaziNabavkuProzor(nabavka);
                                              },
                                              icon: const Icon(
                                                Icons.open_in_new,
                                                size: 18,
                                                color: Colors.black45,
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
              const SizedBox(width: 25),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: boxDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ponuđači',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF102A43),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        odabranaNabavkaDashboard == null
                            ? 'Izaberi javnu nabavku lijevo.'
                            : 'Za: ${odabranaNabavkaDashboard?['naziv'] ?? ''}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 15),
                      Expanded(
                        child: odabranaNabavkaDashboard == null
                            ? const Center(
                                child: Text(
                                  'Klikni na javnu nabavku da vidiš povezane ponuđače.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54),
                                ),
                              )
                            : ponudjaciZaOdabranuNabavku.isEmpty
                            ? const Center(
                                child: Text(
                                  'Za ovu javnu nabavku još nema unesenih ponuđača.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54),
                                ),
                              )
                            : ListView.builder(
                                itemCount: ponudjaciZaOdabranuNabavku.length,
                                itemBuilder: (context, index) {
                                  final ponuda =
                                      ponudjaciZaOdabranuNabavku[index];
                                  final ponudjacRaw = ponuda['ponudjaci'];
                                  final ponudjac = ponudjacRaw is Map
                                      ? Map<String, dynamic>.from(ponudjacRaw)
                                      : <String, dynamic>{};

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        prikaziPonudjacaProzor(ponuda);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF4F7FA),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.business,
                                              color: Color(0xFF1F78B4),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                ponudjac['naziv']?.toString() ??
                                                    'Ponuđač bez naziva',
                                                style: const TextStyle(
                                                  color: Color(0xFF1F78B4),
                                                  decoration:
                                                      TextDecoration.underline,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '#${ponuda['redni_broj'] ?? index + 1}',
                                              style: const TextStyle(
                                                color: Colors.black45,
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
            ],
          ),
        ),
      ],
    );
  }

  Widget javnaNabavkaDropdownZaPonudjace() {
    return DropdownButtonFormField<String>(
      initialValue: odabranaJavnaNabavkaZaPonudjace,
      decoration: InputDecoration(
        labelText: 'Izaberi javnu nabavku',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: javneNabavke.map((nabavka) {
        return DropdownMenuItem<String>(
          value: nabavka['id'].toString(),
          child: Text(nabavka['naziv'] ?? 'Bez naziva'),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          odabranaJavnaNabavkaZaPonudjace = value;
        });
      },
    );
  }

  Future<void> ucitajPonudjaceZaDokumente(String javnaNabavkaId) async {
    final response = await Supabase.instance.client
        .from('ponude')
        .select('''
          id,
          redni_broj,
          datum_dostavljene_ponude,
          valuta,
          ponudjaci (
            id,
            naziv,
            adresa,
            id_broj,
            bankovni_racun,
            kontakt_osoba,
            telefon,
            email
          )
        ''')
        .eq('javna_nabavka_id', javnaNabavkaId)
        .order('redni_broj', ascending: true);

    if (!mounted) return;

    setState(() {
      ponudjaciZaDokumente = List<Map<String, dynamic>>.from(response);
      for (int i = 0; i < dokumentiPonudjaca.length; i++) {
        dokumentiPonudjaca[i] = null;
        dokumentiPonudjacaInfo[i] = null;
      }
    });
  }

  Widget javnaNabavkaDropdownZaDokumente() {
    return DropdownButtonFormField<String>(
      initialValue: odabranaJavnaNabavkaZaDokumente,
      decoration: InputDecoration(
        labelText: 'Izaberi javnu nabavku',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: javneNabavke.map((nabavka) {
        return DropdownMenuItem<String>(
          value: nabavka['id'].toString(),
          child: Text(nabavka['naziv'] ?? 'Bez naziva'),
        );
      }).toList(),
      onChanged: (value) async {
        if (value == null) return;

        setState(() {
          odabranaJavnaNabavkaZaDokumente = value;
          ponudjaciZaDokumente = [];
          for (int i = 0; i < dokumentiPonudjaca.length; i++) {
            dokumentiPonudjaca[i] = null;
          }
        });

        await ucitajPonudjaceZaDokumente(value);
      },
    );
  }

  String ocistiNazivFajla(String naziv) {
    return naziv.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String mimeTypeZaDokument(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  String tipDokumentaZaEkstenziju(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'PDF dokument';
      case 'doc':
      case 'docx':
        return 'Word dokument';
      case 'xls':
      case 'xlsx':
        return 'Excel dokument';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return 'Slika';
      default:
        return 'Dokument';
    }
  }

  Future<void> ucitajDokumentZaPonudjaca(int index) async {
    if (odabranaJavnaNabavkaZaDokumente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prvo izaberi javnu nabavku.')),
      );
      return;
    }

    if (index >= ponudjaciZaDokumente.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nema ponuđača za ovu kolonu.')),
      );
      return;
    }

    final ponuda = ponudjaciZaDokumente[index];
    final ponudjacRaw = ponuda['ponudjaci'];
    final ponudjac = ponudjacRaw is Map
        ? Map<String, dynamic>.from(ponudjacRaw)
        : <String, dynamic>{};

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

    if (result == null || result.files.isEmpty) return;

    final doc = result.files.first;

    if (doc.path == null || doc.path!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nije moguće učitati putanju dokumenta.')),
      );
      return;
    }

    setState(() {
      dokumentiPonudjaca[index] = doc;
      dokumentiPonudjacaInfo[index] = null;
    });

    try {
      final file = File(doc.path!);
      final bytes = await file.readAsBytes();
      final ext = ekstenzijaDokumenta(doc);
      final safeName = ocistiNazivFajla(doc.name);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final storagePath =
          '$odabranaJavnaNabavkaZaDokumente/${ponuda['id']}/$timestamp-$safeName';

      await Supabase.instance.client.storage
          .from('dokumenti-ponuda')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: mimeTypeZaDokument(ext),
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('dokumenti-ponuda')
          .getPublicUrl(storagePath);

      final dokumentRow = await Supabase.instance.client
          .from('dokumenti_ponuda')
          .insert({
            'javna_nabavka_id': odabranaJavnaNabavkaZaDokumente,
            'ponuda_id': ponuda['id'],
            'ponudjac_id': ponudjac['id'],
            'naziv_fajla': doc.name,
            'ekstenzija': ext,
            'tip_dokumenta': tipDokumentaZaEkstenziju(ext),
            'storage_path': storagePath,
            'public_url': publicUrl,
            'ocr_status': 'nije_pokrenut',
          })
          .select()
          .single();

      if (!mounted) return;

      setState(() {
        dokumentiPonudjacaInfo[index] = Map<String, dynamic>.from(dokumentRow);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dokument je sačuvan u bazu: ${doc.name}')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Greška pri uploadu dokumenta: $e')),
      );
    }
  }

  Future<void> pokreniLokalniOcrZaPonudjaca(int index) async {
    print('=== KLIK OCR DUGME ===');
    final doc = dokumentiPonudjaca[index];
    final dokumentInfo = dokumentiPonudjacaInfo[index];

    if (doc == null || doc.path == null || doc.path!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prvo učitaj PDF dokument.')),
      );
      return;
    }

    if (dokumentInfo == null || dokumentInfo['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dokument još nije sačuvan u bazu. Učitaj ga ponovo.'),
        ),
      );
      return;
    }

    final ext = ekstenzijaDokumenta(doc);
    if (ext != 'pdf') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lokalni OCR trenutno radi samo za PDF.')),
      );
      return;
    }

    final dokumentId = dokumentInfo['id'].toString();

    try {
      setState(() {
        dokumentiPonudjacaInfo[index] = {
          ...dokumentInfo,
          'ocr_status': 'u_toku',
        };
      });

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/ocr'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          doc.path!,
          filename: doc.name,
        ),
      );
      print('=== SALJEM NA OCR SERVER ===');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('OCR server greška: ${response.body}');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final ocrPages = data['pages'] is int
          ? data['pages'] as int
          : int.tryParse(data['pages']?.toString() ?? '');
      final ocrPagesJson = data['pages_text'] ?? [];

      if (ocrPagesJson is! List || ocrPagesJson.isEmpty) {
        throw Exception('OCR nije vratio tekst po stranicama.');
      }

      await Supabase.instance.client
          .from('dokumenti_ponuda')
          .update({
            'ocr_status': 'uspjesno',
            'ocr_pages': ocrPages,
            'ocr_pages_json': ocrPagesJson,
          })
          .eq('id', dokumentId);

      if (!mounted) return;

      setState(() {
        dokumentiPonudjacaInfo[index] = {
          ...dokumentInfo,
          'ocr_status': 'uspjesno',
          'ocr_pages': ocrPages,
          'ocr_pages_json': ocrPagesJson,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OCR uspješno obrađen. Broj stranica: ${ocrPages ?? 0}.',
          ),
        ),
      );
    } catch (e) {
      await Supabase.instance.client
          .from('dokumenti_ponuda')
          .update({'ocr_status': 'greska'})
          .eq('id', dokumentId);

      if (!mounted) return;

      setState(() {
        dokumentiPonudjacaInfo[index] = {
          ...dokumentInfo,
          'ocr_status': 'greska',
        };
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška lokalnog OCR-a: $e')));
    }
  }

  String ekstenzijaDokumenta(PlatformFile doc) {
    final fromExtension = doc.extension?.toLowerCase().trim();
    if (fromExtension != null && fromExtension.isNotEmpty) {
      return fromExtension;
    }

    final name = doc.name.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < name.length - 1) {
      return name.substring(dotIndex + 1);
    }

    final path = doc.path?.toLowerCase() ?? '';
    final pathDotIndex = path.lastIndexOf('.');
    if (pathDotIndex != -1 && pathDotIndex < path.length - 1) {
      return path.substring(pathDotIndex + 1);
    }

    return '';
  }

  bool jeSlikaDokument(String ext) {
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'jfif' ||
        ext == 'webp' ||
        ext == 'bmp';
  }

  Widget slikaPreviewWidget(String path, {double? height}) {
    final file = File(path);

    if (!file.existsSync()) {
      return const Center(
        child: Text(
          'Slika nije pronađena na disku.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: height,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.broken_image,
                    size: 54,
                    color: Color(0xFF102A43),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Slika se ne može prikazati u preview prozoru.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      OpenFilex.open(path);
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Otvori sliku'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget maliPrikazPreviewa(PlatformFile? doc) {
    if (doc == null) {
      return const Center(
        child: Text(
          'Dokument nije učitan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    if (doc.path == null || doc.path!.isEmpty) {
      return const Center(child: Text('Nije moguće prikazati dokument.'));
    }

    final ext = ekstenzijaDokumenta(doc);

    if (jeSlikaDokument(ext)) {
      return slikaPreviewWidget(doc.path!, height: double.infinity);
    }

    if (ext == 'pdf') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SfPdfViewer.file(File(doc.path!)),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, size: 54, color: Color(0xFF102A43)),
            const SizedBox(height: 10),
            Text(
              doc.name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Dokument se može otvoriti u programu na računaru.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                OpenFilex.open(doc.path!);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Otvori'),
            ),
          ],
        ),
      ),
    );
  }

  Widget dokumentPonudjacaKolona(int index, Map<String, dynamic>? ponuda) {
    if (ponuda == null) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: boxDecoration(),
          child: const Center(
            child: Text(
              'Nema ponuđača u ovoj koloni.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
      );
    }

    final ponudjacRaw = ponuda['ponudjaci'];
    final ponudjac = ponudjacRaw is Map
        ? Map<String, dynamic>.from(ponudjacRaw)
        : <String, dynamic>{};

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: boxDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ponudjac['naziv']?.toString() ?? 'Ponuđač bez naziva',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF102A43),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                ucitajDokumentZaPonudjaca(index);
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Učitaj dokument'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: maliPrikazPreviewa(dokumentiPonudjaca[index]),
              ),
            ),
            if (dokumentiPonudjaca[index] != null) ...[
              const SizedBox(height: 10),
              if (ekstenzijaDokumenta(dokumentiPonudjaca[index]!) == 'pdf')
                ElevatedButton.icon(
                  onPressed:
                      dokumentiPonudjacaInfo[index]?['ocr_status'] == 'u_toku'
                      ? null
                      : () => pokreniLokalniOcrZaPonudjaca(index),
                  icon: const Icon(Icons.document_scanner),
                  label: Text(
                    dokumentiPonudjacaInfo[index]?['ocr_status'] == 'u_toku'
                        ? 'OCR u toku...'
                        : 'Pokreni lokalni OCR',
                  ),
                ),
              if (dokumentiPonudjacaInfo[index]?['ocr_status'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  'OCR status: ${dokumentiPonudjacaInfo[index]?['ocr_status']}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        dokumentiPonudjacaInfo[index]?['ocr_status'] ==
                            'uspjesno'
                        ? Colors.green
                        : dokumentiPonudjacaInfo[index]?['ocr_status'] ==
                              'greska'
                        ? Colors.red
                        : Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    dokumentiPonudjaca[index] = null;
                    dokumentiPonudjacaInfo[index] = null;
                  });
                },
                icon: const Icon(Icons.close),
                label: const Text('Ukloni dokument'),
              ),
            ],
          ],
        ),
      ),
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
    if (doc.path == null || doc.path!.isEmpty) {
      return const Center(child: Text('Nije moguće prikazati dokument.'));
    }

    final ext = ekstenzijaDokumenta(doc);

    if (jeSlikaDokument(ext)) {
      return slikaPreviewWidget(doc.path!);
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
    final prikazaniPonudjaci = List<Map<String, dynamic>?>.generate(
      3,
      (index) => index < ponudjaciZaDokumente.length
          ? ponudjaciZaDokumente[index]
          : null,
    );

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
                'Učitavanje i pregled dokumenata po ponuđačima za odabranu javnu nabavku.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 20),

              javnaNabavkaDropdownZaDokumente(),

              const SizedBox(height: 25),

              Expanded(
                child: odabranaJavnaNabavkaZaDokumente == null
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: boxDecoration(),
                        child: const Center(
                          child: Text(
                            'Prvo izaberi javnu nabavku da bi se prikazali ponuđači.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      )
                    : ponudjaciZaDokumente.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: boxDecoration(),
                        child: const Center(
                          child: Text(
                            'Za ovu javnu nabavku još nema povezanih ponuđača.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          dokumentPonudjacaKolona(0, prikazaniPonudjaci[0]),
                          const SizedBox(width: 16),
                          dokumentPonudjacaKolona(1, prikazaniPonudjaci[1]),
                          const SizedBox(width: 16),
                          dokumentPonudjacaKolona(2, prikazaniPonudjaci[2]),
                        ],
                      ),
              ),
            ],
          ),
        ),

        Positioned(
          right: 0,
          bottom: 0,
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
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
                DropdownButtonFormField<String>(
                  initialValue: program,
                  decoration: InputDecoration(
                    labelText: 'Izaberi program',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: programi.map((item) {
                    return DropdownMenuItem(value: item, child: Text(item));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      program = value!;
                    });
                  },
                ),

                const SizedBox(height: 16),

                input('Naziv nabavke', nazivController),
                organizacijaDropdown(),
                const SizedBox(height: 16),
                input('Projekat', projekatController),
                input('Donator', donatorController),
                input('Osnov za pokretanje nabavke', osnovPokretanjaController),
                TextField(
                  controller: vrijemePokretanjaController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [vrijemePokretanjaMask],
                  decoration: InputDecoration(
                    labelText: 'Vrijeme pokretanja nabavke',
                    hintText: '__:__ __.__.____',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
          'Unos i pregled ponuđača za odabrani postupak javne nabavke.',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),

        const SizedBox(height: 20),

        javnaNabavkaDropdownZaPonudjace(),

        const SizedBox(height: 25),

        Expanded(
          child: odabranaJavnaNabavkaZaPonudjace == null
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: boxDecoration(),
                  child: const Center(
                    child: Text(
                      'Prvo izaberi javnu nabavku da bi mogao unositi ponuđače.',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                  ),
                )
              : Column(
                  children: [
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
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            selectedIndex = 0;
                          });
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('OK'),
                      ),
                    ),
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
                controller: ponudjacNazivControllers[index],
                enabled: !ponudjacSacuvan[index],
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
                controller: ponudjacAdresaControllers[index],
                enabled: !ponudjacSacuvan[index],
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
                controller: ponudjacIdBrojControllers[index],
                enabled: !ponudjacSacuvan[index],
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
                controller: ponudjacRacunControllers[index],
                enabled: !ponudjacSacuvan[index],
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
                      controller: ponudjacKontaktControllers[index],
                      enabled: !ponudjacSacuvan[index],
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
                      controller: ponudjacTelefonControllers[index],
                      enabled: !ponudjacSacuvan[index],
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
                      controller: ponudjacEmailControllers[index],
                      enabled: !ponudjacSacuvan[index],
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
                controller: ponudjacDatumControllers[index],
                enabled: !ponudjacSacuvan[index],
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
                initialValue: ponudjacValuta[index],
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
                onChanged: ponudjacSacuvan[index]
                    ? null
                    : (value) {
                        setState(() {
                          ponudjacValuta[index] = value!;
                        });
                      },
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: ponudjacSacuvan[index]
                    ? null
                    : () {
                        sacuvajPonudjaca(index);
                      },
                icon: const Icon(Icons.save),
                label: Text(
                  ponudjacSacuvan[index] ? 'Ponuđač sačuvan' : 'Spasi ponuđača',
                ),
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
        initialValue: vrstaNabavke,
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
        initialValue: organizacija,
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
        initialValue: value,
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
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
