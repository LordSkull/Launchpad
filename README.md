# Launchpad

Una versione modernizzata e più semplice da usare del progetto originale **Dan12/Launchpad**.

Launchpad è un'applicazione web che simula un controller Launchpad direttamente nel browser: puoi suonare sample con tastiera e mouse, cambiare sound pack, aggiungere nuove canzoni e gestire quelle installate senza modificare manualmente il codice.

> **Stato del progetto:** questa fork nasce da una codebase legacy basata originariamente su Ruby on Rails 4.2.  
> Il progetto è stato progressivamente modernizzato ed è attualmente basato su **Ruby 3.3.12** e **Rails 7.1.6**.
>
> La modernizzazione è ancora in corso, con particolare attenzione a sicurezza, semplificazione dell'architettura e rimozione delle dipendenze legacy residue.

---

## Funzionalità

- Launchpad virtuale utilizzabile direttamente dal browser
- Controllo tramite tastiera e mouse
- Riproduzione audio tramite Howler.js
- Supporto a 4 chain da 48 pad ciascuna
- Sound pack built-in
- Aggiunta di nuove canzoni tramite Song Builder
- Validazione automatica dei manifest e dei sound pack
- Installazione delle canzoni senza modificare `keyboard.js`
- Gestione delle canzoni installate
- Rimozione delle user song tramite **Manage Songs**
- Persistenza delle canzoni utente in `user_data/`
- Ambiente Docker riproducibile
- Launcher Windows per avvio, stop e visualizzazione log
- Suite automatica di test Rails

---

# Installazione rapida

## Requisito

Per utilizzare Launchpad non è necessario installare manualmente Ruby, Rails, Bundler, SQLite o altre dipendenze.

Serve solamente:

**Docker Desktop**

Puoi scaricarlo dal sito ufficiale:

https://www.docker.com/products/docker-desktop/

Dopo l'installazione, avvia Docker Desktop e attendi che Docker sia pronto.

---

## Avviare Launchpad su Windows

Scarica o clona questa repository.

Con Git:

```powershell
git clone https://github.com/LordSkull/Launchpad.git
cd Launchpad
```

Poi fai doppio clic su:

```text
START_LAUNCHPAD.bat
```

Il launcher:

1. verifica che Docker sia disponibile;
2. avvia o ricostruisce l'ambiente Launchpad se necessario;
3. prepara l'ambiente Rails locale;
4. avvia il server web;
5. apre il browser su:

```text
http://localhost:3000
```

### Primo avvio

Il primo avvio può richiedere alcuni minuti perché Docker deve scaricare l'immagine Ruby e installare le dipendenze del progetto.

Gli avvii successivi sono normalmente molto più rapidi.

---

## Fermare Launchpad

Fai doppio clic su:

```text
STOP_LAUNCHPAD.bat
```

Le canzoni aggiunte dall'utente vengono mantenute.

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

Si aprirà il **Song Builder**.

Il builder permette di:

- scegliere uno ZIP contenente i sample;
- impostare nome e BPM;
- configurare le 4 chain;
- assegnare i sample ai 48 pad;
- impostare i pad `hold to play`;
- configurare gruppi di pad collegati;
- validare il pacchetto;
- installare direttamente la canzone.

Non è necessario modificare manualmente JavaScript o altri file del progetto.

---

## Struttura dello ZIP

Il sound pack utilizza una struttura come questa:

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

Per ottenere risultati migliori è consigliato partire da materiale già preparato, ad esempio:

- Launchpad project file;
- sample pack;
- stem;
- loop;
- vocal chop;
- effetti;
- one-shot.

La separazione automatica di una canzone completa in voce, batteria, basso e altri stem può essere utile come punto di partenza, ma normalmente è comunque necessario scegliere e tagliare manualmente le parti musicalmente interessanti.

---

# Gestire le canzoni

Dalla home premi:

```text
Manage Songs
```

La pagina distingue tra due categorie.

### Built-in songs

Sono le canzoni incluse direttamente nel progetto.

Non vengono rimosse dalla normale interfaccia.

### Your songs

Sono le canzoni installate dall'utente.

Per rimuoverne una premi:

```text
Remove
```

e conferma l'operazione.

La configurazione e il relativo sound pack vengono eliminati dal relativo spazio utente.

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
- ricostruire il container Docker non cancella normalmente le user song;
- aggiornare l'applicazione è più semplice;
- le song installate possono essere gestite senza modificare la repository.

---

# Architettura delle canzoni

Launchpad gestisce attualmente due tipi principali di canzoni.

```text
Built-in songs
    ↓
metadata JavaScript
    ↓
ZIP statici
    ↓
browser

User songs
    ↓
Song Builder
    ↓
manifest + ZIP
    ↓
LocalSongsController
    ↓
SongManifest
    ↓
ZipEntries
    ↓
UserSongStore
    ↓
user_data/songs
    ↓
browser
```

Il vecchio sistema basato sul model ActiveRecord `Song` è stato rimosso.

Le user song moderne non dipendono dal database Rails.

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

Docker ricostruirà automaticamente l'ambiente quando necessario.

I dati presenti in `user_data/` rimangono separati dal codice del progetto.

---

# Risoluzione dei problemi

## Docker non trovato

Se compare:

```text
[ERROR] Docker was not found.
```

installa Docker Desktop, avvialo e riprova.

---

## Docker è installato ma Launchpad non parte

Assicurati che Docker Desktop sia aperto e abbia completato l'avvio.

Poi prova nuovamente:

```text
START_LAUNCHPAD.bat
```

---

## La porta 3000 è già utilizzata

Controlla che non ci sia già un'altra istanza Rails o Launchpad attiva.

Puoi fermare il container Launchpad con:

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

Il Song Builder e il backend eseguono controlli sul pacchetto.

Verifica in particolare:

- struttura dello ZIP;
- cartelle delle chain;
- nomi dei sample;
- mapping dei pad;
- manifest della canzone;
- eventuali valori o indici non validi.

Per maggiori dettagli puoi consultare i log:

```text
CHECK_LAUNCHPAD_LOGS.bat
```

---

# Per sviluppatori

## Stack attuale

La baseline attuale utilizza:

```text
Ruby          3.3.12
Rails         7.1.6
Bundler       2.4.22
Puma
Sprockets
SQLite        1.4.2

JavaScript
Howler.js
Zip.js
```

Il progetto deriva da una codebase molto più vecchia e alcune dipendenze e parti dell'architettura sono ancora in fase di revisione.

Durante la modernizzazione sono già state eliminate diverse dipendenze e componenti legacy non più utilizzati, tra cui il vecchio sistema di autenticazione, il MIDI editor legacy, SassC, CoffeeScript, `sdoc`, `byebug` e altri componenti storici.

---

## Avvio tramite terminale

Build e avvio:

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
docker compose exec launchpad bundle exec rails console
```

Stop:

```bash
docker compose down
```

---

## Test

La repository include una suite automatica di test Rails.

Eseguila con:

```bash
docker compose exec launchpad bundle exec rails test
```

La suite copre, tra le altre cose:

- parsing e validazione dei manifest;
- `UserSongStore`;
- parsing ZIP;
- API HTTP delle user song;
- installazione e rimozione;
- endpoint legacy rimossi;
- isolamento dei dati utilizzati dai test.

---

# Struttura principale

```text
Launchpad/
├── app/
│   ├── assets/
│   │   ├── javascripts/
│   │   └── stylesheets/
│   ├── controllers/
│   ├── services/
│   └── views/
├── config/
├── db/
├── public/
│   ├── song_builder.html
│   └── ...
├── script/
├── test/
├── user_data/
│   └── songs/
├── docker/
├── Dockerfile
├── compose.yaml
├── START_LAUNCHPAD.bat
├── STOP_LAUNCHPAD.bat
├── CHECK_LAUNCHPAD_LOGS.bat
└── README.md
```

La struttura può evolvere ulteriormente durante la modernizzazione.

---

# Roadmap

La priorità del progetto è preservare il comportamento del Launchpad mentre la codebase viene modernizzata e resa più robusta.

- [x] rendere il progetto nuovamente eseguibile;
- [x] creare un ambiente Docker riproducibile;
- [x] aggiungere un Song Builder;
- [x] validare manifest e sound pack;
- [x] installare canzoni dalla UI;
- [x] separare le user song dal codice;
- [x] aggiungere Manage Songs;
- [x] aggiungere Remove Song;
- [x] aggiungere test automatici;
- [x] caratterizzare l'API delle user song;
- [x] rimuovere il sistema di autenticazione legacy;
- [x] rimuovere il MIDI editor legacy;
- [x] rimuovere i model ActiveRecord legacy;
- [x] rimuovere diverse dipendenze Ruby non più utilizzate;
- [x] migrare da Rails 4.x a Rails 7.1;
- [x] migrare da Ruby 2.x a Ruby 3.3;
- [ ] completare il security hardening;
- [ ] migliorare la protezione dei percorsi filesystem e dei symlink;
- [ ] introdurre limiti più robusti per ZIP e manifest;
- [ ] rendere le installazioni delle user song atomiche;
- [ ] migliorare la gestione degli errori HTTP;
- [ ] rimuovere ActiveRecord e SQLite se non più necessari;
- [ ] aggiungere CI con GitHub Actions;
- [ ] migliorare l'interfaccia del Song Builder;
- [ ] modernizzare progressivamente il frontend;
- [ ] continuare l'aggiornamento verso versioni Rails più recenti.

---

# Sicurezza

Launchpad nasce da un'applicazione Rails legacy ed è ancora in fase di hardening.

L'ambiente Docker fornito è pensato principalmente per:

- utilizzo locale;
- sviluppo;
- test.

Per impostazione predefinita il servizio Docker viene pubblicato solamente sull'interfaccia locale:

```text
127.0.0.1:3000
```

e non viene quindi esposto automaticamente alla rete LAN.

Non è comunque consigliato esporre direttamente l'applicazione su Internet finché non sarà completata la revisione delle superfici di sicurezza.

Le aree attualmente oggetto di revisione includono:

- rendering sicuro dei dati controllabili dall'utente;
- protezione CSRF;
- confinamento dei percorsi filesystem;
- gestione dei symlink;
- installazioni atomiche;
- limiti sulle risorse ZIP;
- limiti sui manifest;
- gestione degli errori delle API.

---

# Crediti

Questo progetto deriva dalla repository originale:

**Dan12/Launchpad**

La fork mantiene il concetto originale di Launchpad virtuale e aggiunge strumenti per facilitarne installazione, utilizzo, manutenzione e gestione delle canzoni.

Repository della fork:

https://github.com/LordSkull/Launchpad

---

# Licenza

Il progetto originale è distribuito con licenza MIT.

La licenza del codice non implica automaticamente diritti sul materiale audio incluso o utilizzato con il progetto.

Controlla sempre separatamente i diritti relativi a:

- sample audio;
- sound pack;
- canzoni;
- stem;
- project file di terze parti.

Il fatto che un sound pack sia disponibile online non implica automaticamente il diritto di ridistribuirlo.