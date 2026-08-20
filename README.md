# Launchpad

Una versione modernizzata e più semplice da usare del progetto originale **Dan12/Launchpad**.

Launchpad è un'applicazione web che simula un controller Launchpad direttamente nel browser: puoi suonare sample con tastiera e mouse, cambiare sound pack, aggiungere nuove canzoni e gestire quelle installate senza modificare manualmente il codice.

> Stato del progetto: questa fork parte da una codebase legacy basata su Ruby on Rails 4.2 e Ruby 2.6. L'obiettivo è mantenere il progetto funzionante mentre viene modernizzato progressivamente.

---

## Funzionalità

- Launchpad virtuale utilizzabile da browser
- Controllo tramite tastiera
- Riproduzione audio tramite Howler.js
- Supporto a 4 chain da 48 pad ciascuna
- Aggiunta di nuove canzoni tramite interfaccia web
- Validazione automatica dei sound pack
- Installazione delle canzoni senza modificare `keyboard.js`
- Gestione delle canzoni installate
- Rimozione delle canzoni dalla pagina **Manage Songs**
- Persistenza delle canzoni utente in `user_data/`
- Avvio semplificato tramite Docker

---

# Installazione rapida

## Requisito

Per utilizzare Launchpad non è necessario installare Ruby, Rails, Bundler, SQLite o altre dipendenze manualmente.

Serve solamente:

**Docker Desktop**

Scaricalo e installalo dal sito ufficiale Docker:

https://www.docker.com/products/docker-desktop/

Dopo l'installazione, avvia Docker Desktop e attendi che Docker sia pronto.

---

## Avviare Launchpad su Windows

Scarica o clona questa repository.

Se usi Git:

```powershell
git clone https://github.com/LordSkull/Launchpad.git
cd Launchpad
```

Poi fai doppio clic su:

```text
START_LAUNCHPAD.bat
```

Il launcher:

1. verifica che Docker sia installato;
2. avvia l'ambiente Launchpad;
3. prepara automaticamente il database al primo avvio;
4. avvia Rails;
5. apre il browser su:

```text
http://localhost:3000
```

### Primo avvio

Il primo avvio può richiedere alcuni minuti perché Docker deve scaricare l'immagine Ruby e installare le dipendenze del progetto.

Gli avvii successivi sono molto più rapidi.

---

## Fermare Launchpad

Fai doppio clic su:

```text
STOP_LAUNCHPAD.bat
```

Le canzoni aggiunte dall'utente e il database locale vengono mantenuti.

---

## Visualizzare i log

Se Launchpad non parte, fai doppio clic su:

```text
CHECK_LAUNCHPAD_LOGS.bat
```

Verranno mostrate le ultime righe dei log del container.

---

# Come si usa

Apri:

```text
http://localhost:3000
```

La pagina principale contiene il Launchpad virtuale e l'elenco delle canzoni disponibili.

Puoi utilizzare:

- tastiera del computer;
- mouse;
- controlli della pagina.

Il Launchpad è organizzato in **4 chain**, ognuna composta da **48 pad**.

---

# Aggiungere una canzone

Dalla pagina principale premi:

```text
+ Add Song
```

Si aprirà il Song Builder.

Il builder permette di:

- scegliere uno ZIP contenente i sample;
- impostare nome e BPM;
- configurare le 4 chain;
- assegnare i sample ai 48 pad;
- impostare i pad `hold to play`;
- configurare gruppi di pad collegati;
- validare il pacchetto;
- installare direttamente la canzone.

Non è necessario modificare JavaScript manualmente.

---

## Struttura dello ZIP

Il sound pack deve avere questa struttura:

```text
sounds/
├── chain1/
│   ├── kick.mp3
│   ├── vocal.mp3
│   └── ...
├── chain2/
│   └── ...
├── chain3/
│   └── ...
└── chain4/
    └── ...
```

Ogni chain può contenere i sample utilizzati dai suoi 48 pad.

Il Song Builder permette poi di associare ogni file al pad desiderato.

---

## Sample e project file

Per ottenere risultati migliori è consigliato partire da:

- Launchpad project file già esistenti;
- sample pack;
- stem già tagliati;
- loop;
- vocal chop;
- effetti;
- one-shot.

Separare automaticamente una canzone completa in voce, batteria e basso può essere utile come punto di partenza, ma normalmente è comunque necessario scegliere e tagliare manualmente le parti musicalmente interessanti.

---

# Gestire le canzoni

Dalla home premi:

```text
Manage Songs
```

La pagina distingue tra:

### Built-in songs

Canzoni incluse nel progetto.

Non vengono rimosse dalla normale interfaccia.

### Your songs

Canzoni installate dall'utente.

Per rimuoverne una premi:

```text
Remove
```

e conferma l'operazione.

La configurazione e il relativo sound pack verranno eliminati automaticamente.

---

# Dove vengono salvate le canzoni

Le canzoni installate dall'utente vengono conservate in:

```text
user_data/
└── songs/
    ├── nome_canzone/
    │   ├── song.json
    │   └── sounds.zip
    └── ...
```

Questi dati sono separati dal codice dell'applicazione.

Questo significa che:

- installare una canzone non modifica `keyboard.js`;
- rimuovere una canzone non modifica il sorgente;
- ricostruire il container Docker non cancella le canzoni;
- aggiornare l'applicazione è più semplice.

---

# Aggiornare il progetto

Se hai clonato la repository tramite Git:

```powershell
git pull
```

poi riavvia Launchpad con:

```text
START_LAUNCHPAD.bat
```

Docker ricostruirà automaticamente l'immagine se necessario.

I dati presenti in `user_data/` non vengono cancellati.

---

# Risoluzione dei problemi

## Docker non trovato

Se compare:

```text
[ERROR] Docker was not found.
```

installa Docker Desktop e riapri il launcher.

---

## Docker è installato ma non parte

Assicurati che Docker Desktop sia aperto e abbia completato l'avvio.

Poi riprova:

```text
START_LAUNCHPAD.bat
```

---

## La porta 3000 è già utilizzata

Controlla che non ci sia già un'altra istanza Rails o Launchpad attiva.

Puoi fermare il container con:

```text
STOP_LAUNCHPAD.bat
```

---

## Launchpad non carica correttamente dopo una modifica

Prova un hard refresh del browser:

```text
Ctrl + Shift + R
```

---

## L'audio non parte automaticamente

I browser moderni possono impedire l'avvio automatico dell'audio.

Clicca una volta nella pagina e poi premi uno dei pad.

---

## Una canzone non viene installata

Il Song Builder esegue una validazione automatica.

Controlla in particolare:

- struttura dello ZIP;
- presenza delle cartelle `chain1` ... `chain4`;
- nomi dei sample;
- mapping dei pad;
- eventuali indici non validi.

---

# Per sviluppatori

## Stack attuale

La baseline attuale utilizza:

```text
Ruby        2.7.8
Rails       6.1.7.10
Bundler     2.4.22
SQLite      1.4.2
JavaScript
Howler.js
Zip.js
```

Questo stack è legacy e non rappresenta l'obiettivo finale del progetto.

Per questo motivo è consigliato utilizzare Docker invece di installare manualmente l'ambiente Ruby sul sistema host.

---

## Avvio tramite terminale

```bash
docker compose up -d --build
```

Log:

```bash
docker compose logs -f launchpad
```

Shell nel container:

```bash
docker compose exec launchpad bash
```

Rails console:

```bash
docker compose exec launchpad bundle _2.4.22_ exec rails console
```

Stop:

```bash
docker compose down
```

---

# Struttura principale

```text
Launchpad/
├── app/
│   ├── assets/
│   ├── controllers/
│   ├── models/
│   └── views/
├── config/
├── public/
│   ├── song_builder.html
│   └── ...
├── script/
├── user_data/
│   └── songs/
├── docker/
├── Dockerfile
├── compose.yaml
├── START_LAUNCHPAD.bat
├── STOP_LAUNCHPAD.bat
└── README.md
```

---

# Roadmap

La priorità è mantenere il comportamento del progetto mentre viene modernizzato.

Obiettivi principali:

- [x] rendere il progetto nuovamente eseguibile;
- [x] aggiungere un Song Builder;
- [x] validare i sound pack;
- [x] installare canzoni dalla UI;
- [x] separare le canzoni utente dal codice;
- [x] aggiungere Manage Songs;
- [x] aggiungere Remove Song;
- [x] preparare un ambiente Docker;
- [ ] aggiungere test automatici;
- [ ] aggiungere CI con GitHub Actions;
- [ ] migliorare il formato dei sound pack;
- [ ] migliorare l'interfaccia del Song Builder;
- [ ] modernizzare il frontend;
- [ ] migrare progressivamente Rails;
- [ ] migrare a una versione Ruby supportata;
- [ ] eliminare le dipendenze legacy non necessarie.

---

# Sicurezza

La versione attuale nasce da un'applicazione Rails legacy.

Il container Docker fornito è pensato principalmente per:

- utilizzo locale;
- sviluppo;
- test.

Non è consigliato esporre direttamente questa versione su Internet fino al completamento della modernizzazione dello stack e della revisione delle superfici di sicurezza.

---

# Crediti

Questo progetto deriva dalla repository originale:

**Dan12/Launchpad**

La fork mantiene il concetto originale di Launchpad virtuale e aggiunge strumenti per facilitarne installazione, utilizzo e gestione delle canzoni.

---

# Licenza

Il progetto originale è distribuito con licenza MIT.

Controlla sempre separatamente i diritti relativi a:

- sample audio;
- sound pack;
- canzoni;
- project file di terze parti.

Il fatto che un sound pack sia disponibile online non implica automaticamente il diritto di ridistribuirlo.
