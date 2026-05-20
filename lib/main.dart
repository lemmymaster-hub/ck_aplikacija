import 'package:flutter/material.dart';

void main() {
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
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  List<bool> prikaziFormu = [false, false, false];
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
      child: selectedIndex == 1
          ? javneNabavkeScreen()
          : selectedIndex == 2
          ? ponudjaciScreen()
          : dashboardScreen(),
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
        const SizedBox(height: 30),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 1.7,
            children: [
              card(Icons.gavel, 'Aktivne nabavke', '0'),
              card(Icons.business, 'Ponuđači', '0'),
              card(Icons.description, 'Dokumenti', '0'),
              card(Icons.auto_awesome, 'AI analiza', 'Spremna'),
              card(Icons.picture_as_pdf, 'Izvještaji', '0'),
              card(Icons.settings, 'Podešavanja', 'Aktivna'),
            ],
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
                const SizedBox(height: 25),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Nabavka je privremeno sačuvana.'),
                          ),
                        );
                      },
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
