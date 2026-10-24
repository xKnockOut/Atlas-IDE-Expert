# Prüfregeln

Erzeugt von `Tools/Update-RuleCatalog.ps1` aus dem Regelkatalog. Nicht von Hand ändern.

## Gruppen

| Gruppe | Regeln |
|---|---|
| [Fehler finden](#gruppe-find-bugs) | 75 |
| [Exceptions](#gruppe-exceptions) | 8 |
| [Threads](#gruppe-threads) | 15 |
| [Datenbank](#gruppe-database) | 5 |
| [Compiler vorab](#gruppe-compiler) | 77 |
| [Robustheit und Muster](#gruppe-robustness) | 13 |
| [Performance](#gruppe-performance) | 6 |
| [Sicherheit](#gruppe-security) | 11 |
| [Komponenten](#gruppe-components) | 8 |
| [Formulare und Daten](#gruppe-forms) | 14 |
| [Architektur](#gruppe-architecture) | 4 |
| [Stil und Metriken](#gruppe-style) | 48 |
| [Packages und Tests](#gruppe-packages) | 3 |
| [Atlas intern](#gruppe-internal) | 4 |

<a id="gruppe-find-bugs"></a>
### Fehler finden

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`result-not-set`](#result-not-set) | Funktionsergebnis eventuell nicht gesetzt | Bug | Warnung |
| [`possibly-uninitialized`](#possibly-uninitialized) | Variable eventuell nicht initialisiert | Bug | Warnung |
| [`unreachable-code`](#unreachable-code) | Unerreichbarer Code | Bug | Warnung |
| [`duplicate-assignment`](#duplicate-assignment) | Feld oder Property wird zweimal gesetzt | Bug | Warnung |
| [`declared-not-implemented`](#declared-not-implemented) | Deklariert, aber nicht implementiert | Bug | Fehler |
| [`implemented-not-declared`](#implemented-not-declared) | Implementiert, aber nicht deklariert | Bug | Fehler |
| [`destroy-without-override`](#destroy-without-override) | Destroy ohne override | Bug | Warnung |
| [`setter-recursion`](#setter-recursion) | Setter oder Getter ruft sich selbst auf | Bug | Fehler |
| [`hides-virtual`](#hides-virtual) | Methode verdeckt virtuelle Methode | Bug | Warnung |
| [`virtual-instead-of-override`](#virtual-instead-of-override) | virtual statt override | Bug | Warnung |
| [`captured-loop-variable`](#captured-loop-variable) | Erfasste Schleifenvariable | Bug | Warnung |
| [`interface-guid`](#interface-guid) | Interface ohne GUID | Bug | Warnung |
| [`duplicate-interface-guid`](#duplicate-interface-guid) | Zwei Interfaces mit derselben GUID | Bug | Fehler |
| [`self-assignment`](#self-assignment) | Zuweisung an sich selbst | Bug | Warnung |
| [`exception-not-raised`](#exception-not-raised) | Exception erzeugt, aber nicht ausgelöst | Bug | Warnung |
| [`assert-side-effect`](#assert-side-effect) | Assert mit Seiteneffekt | Bug | Warnung |
| [`ifthen-side-effect`](#ifthen-side-effect) | IfThen wertet beide Zweige aus | Bug | Warnung |
| [`int32-mul-overflow`](#int32-mul-overflow) | Int32-Multiplikation an Int64 zugewiesen | Bug | Warnung |
| [`sizeof-pointer`](#sizeof-pointer) | SizeOf eines Zeigers in Move oder FillChar | Bug | Fehler |
| [`char-to-pchar`](#char-to-pchar) | Char nach PChar umgewandelt | Bug | Fehler |
| [`unrelated-class-cast`](#unrelated-class-cast) | Harte Umwandlung zwischen nicht verwandten Klassen | Bug | Warnung |
| [`first-char-address`](#first-char-address) | Adresse des ersten Zeichens über S[1] | Bug | Warnung |
| [`float-equality`](#float-equality) | Gleitkommavergleich mit = oder <> | Bug | Hinweis |
| [`constructor-on-instance`](#constructor-on-instance) | Konstruktor auf einer Instanz aufgerufen | Bug | Warnung |
| [`format-args`](#format-args) | Formatstring passt nicht zu den Argumenten | Bug | Fehler |
| [`unresolved-identifier`](#unresolved-identifier) | Nicht deklarierter Bezeichner | Bug | Warnung |
| [`type-used-before-declaration`](#type-used-before-declaration) | Typ vor seiner Deklaration benutzt | Bug | Fehler |
| [`field-not-freed`](#field-not-freed) | Feld erzeugt, aber nie freigegeben | Bug | Warnung |
| [`owned-field-free-unclear`](#owned-field-free-unclear) | Unklar, ob ein erzeugtes Feld freigegeben werden muss | Bug | Hinweis |
| [`operator-precedence`](#operator-precedence) | Vorrang von not übersehen | Bug | Warnung |
| [`empty-statement`](#empty-statement) | Leere Anweisung nach then, do oder else | Bug | Warnung |
| [`loop-off-by-one`](#loop-off-by-one) | Schleife läuft einen Schritt zu weit | Bug | Warnung |
| [`collection-modified-in-loop`](#collection-modified-in-loop) | Liste in der eigenen Schleife verändert | Bug | Warnung |
| [`use-after-free`](#use-after-free) | Objekt nach Free weiter benutzt | Bug | Fehler |
| [`deref-before-nil-check`](#deref-before-nil-check) | Erst benutzt, dann auf nil geprüft | Bug | Warnung |
| [`field-free-without-nil`](#field-free-without-nil) | Feld freigegeben, Verweis bleibt stehen | Bug | Warnung |
| [`missing-inherited`](#missing-inherited) | Konstruktor oder Destruktor ohne inherited | Bug | Warnung |
| [`inherited-order`](#inherited-order) | inherited an der falschen Stelle | Bug | Warnung |
| [`inherited-wrong-method`](#inherited-wrong-method) | inherited ruft eine andere Methode | Bug | Warnung |
| [`getter-side-effect`](#getter-side-effect) | Getter verändert den Zustand | Code Smell | Warnung |
| [`equals-without-gethashcode`](#equals-without-gethashcode) | Equals ohne GetHashCode | Bug | Warnung |
| [`destroy-called-directly`](#destroy-called-directly) | Destroy statt Free aufgerufen | Bug | Warnung |
| [`managed-type-raw-memory`](#managed-type-raw-memory) | FillChar, Move oder GetMem auf verwaltete Typen | Bug | Fehler |
| [`pchar-of-temporary`](#pchar-of-temporary) | PChar auf einen temporären String | Bug | Warnung |
| [`out-param-read`](#out-param-read) | out-Parameter gelesen, bevor er gesetzt ist | Bug | Warnung |
| [`noreturn-returns`](#noreturn-returns) | noreturn-Routine kann normal zurückkehren | Bug | Warnung |
| [`stringlist-unsorted`](#stringlist-unsorted) | Find oder Duplicates auf einer unsortierten TStringList | Bug | Warnung |
| [`writeln-in-gui-app`](#writeln-in-gui-app) | Writeln in einem Programm ohne Konsole | Bug | Warnung |
| [`duplicate-condition`](#duplicate-condition) | Doppelte Bedingung oder gleiche Zweige | Bug | Warnung |
| [`case-missing-enum-value`](#case-missing-enum-value) | case über Aufzählung ohne alle Werte | Bug | Warnung |
| [`pair-without-finally`](#pair-without-finally) | Paarige Aufrufe ohne try/finally | Bug | Warnung |
| [`unchecked-conversion`](#unchecked-conversion) | Umwandlung einer Benutzereingabe ohne Prüfung | Bug | Hinweis |
| [`dictionary-get-without-check`](#dictionary-get-without-check) | Dictionary-Zugriff ohne Prüfung des Schlüssels | Bug | Hinweis |
| [`event-call-without-assigned`](#event-call-without-assigned) | Ereignis ohne Assigned-Prüfung aufgerufen | Bug | Warnung |
| [`owned-item-freed`](#owned-item-freed) | Element einer besitzenden Liste zusätzlich freigegeben | Bug | Fehler |
| [`create-without-assignment`](#create-without-assignment) | Objekt erzeugt und sofort verloren | Bug | Warnung |
| [`raw-memory-leak`](#raw-memory-leak) | GetMem oder New ohne Freigabe | Bug | Warnung |
| [`stringlist-objects-leak`](#stringlist-objects-leak) | Objekte in einer TStringList ohne Besitz | Bug | Warnung |
| [`message-handler-without-inherited`](#message-handler-without-inherited) | Message-Handler ohne inherited | Bug | Warnung |
| [`string-index-base`](#string-index-base) | String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen | Bug | Warnung |
| [`delimited-text-without-strict`](#delimited-text-without-strict) | DelimitedText ohne StrictDelimiter | Bug | Warnung |
| [`self-as-interface-in-constructor`](#self-as-interface-in-constructor) | Self während der Konstruktion als Interface weitergegeben | Bug | Warnung |
| [`unchecked-enum-cast`](#unchecked-enum-cast) | Zahl ungeprüft in Aufzählung umgewandelt | Bug | Hinweis |
| [`createprocess-readonly-commandline`](#createprocess-readonly-commandline) | CreateProcess mit unveränderlicher Befehlszeile | Bug | Fehler |
| [`form-access-before-create`](#form-access-before-create) | Zugriff auf ein Formular, das noch nicht erzeugt ist | Bug | Warnung |
| [`destructor-not-nil-safe`](#destructor-not-nil-safe) | Destruktor benutzt Felder, die nil sein können | Bug | Warnung |
| [`handle-leak`](#handle-leak) | Windows-Handle wird nicht geschlossen | Bug | Warnung |
| [`component-interface-dangling`](#component-interface-dangling) | Komponente als Interface gespeichert und freigegeben | Bug | Warnung |
| [`constant-condition`](#constant-condition) | Bedingung ist immer gleich | Bug | Warnung |
| [`infinite-loop`](#infinite-loop) | Schleife ohne Ausgang | Bug | Fehler |
| [`loop-condition-unchanged`](#loop-condition-unchanged) | Schleifenbedingung ändert sich im Rumpf nie | Bug | Warnung |
| [`loop-runs-at-most-once`](#loop-runs-at-most-once) | Schleife läuft höchstens einmal | Bug | Warnung |
| [`unconditional-recursion`](#unconditional-recursion) | Rekursion ohne Abbruch | Bug | Fehler |
| [`pos-arguments-swapped`](#pos-arguments-swapped) | Argumente von Pos vertauscht | Bug | Warnung |
| [`integer-division-to-float`](#integer-division-to-float) | Ganzzahldivision an Gleitkommazahl | Bug | Warnung |

<a id="gruppe-exceptions"></a>
### Exceptions

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`empty-except`](#empty-except) | Leerer except-Block | Code Smell | Warnung |
| [`generic-exception-raised`](#generic-exception-raised) | Allgemeine Exception ausgelöst | Code Smell | Hinweis |
| [`catch-all-without-raise`](#catch-all-without-raise) | Exception-Handler ohne erneutes raise | Code Smell | Warnung |
| [`exception-freed`](#exception-freed) | Exception-Objekt manuell freigegeben | Bug | Fehler |
| [`raise-in-finally`](#raise-in-finally) | raise in einem finally-Block | Bug | Warnung |
| [`exception-in-destructor`](#exception-in-destructor) | raise im Destruktor | Bug | Warnung |
| [`except-handler-order`](#except-handler-order) | Allgemeiner Exception-Handler vor speziellem | Bug | Warnung |
| [`reraise-exception-object`](#reraise-exception-object) | raise E statt raise im Handler | Code Smell | Warnung |

<a id="gruppe-threads"></a>
### Threads

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`thread-vcl-access`](#thread-vcl-access) | VCL-Zugriff aus einem Thread | Bug | Warnung |
| [`lock-without-finally`](#lock-without-finally) | Sperre ohne try/finally | Bug | Warnung |
| [`thread-use-after-free-on-terminate`](#thread-use-after-free-on-terminate) | Thread nach dem Start mit FreeOnTerminate benutzt | Bug | Warnung |
| [`thread-free-with-free-on-terminate`](#thread-free-with-free-on-terminate) | Free auf einem Thread mit FreeOnTerminate | Bug | Fehler |
| [`synchronize-in-destructor`](#synchronize-in-destructor) | Synchronize im Destruktor eines Threads | Bug | Warnung |
| [`thread-resume-suspend`](#thread-resume-suspend) | Veraltetes TThread.Resume/Suspend | Code Smell | Warnung |
| [`threadvar-managed`](#threadvar-managed) | threadvar mit verwaltetem Typ | Bug | Warnung |
| [`processmessages-in-loop`](#processmessages-in-loop) | Application.ProcessMessages in Schleifen | Code Smell | Hinweis |
| [`queue-nil-in-package`](#queue-nil-in-package) | TThread.Queue(nil, …) in einem Package | Bug | Warnung |
| [`blocking-call-in-main-thread`](#blocking-call-in-main-thread) | Blockierender Aufruf im Hauptthread | Code Smell | Warnung |
| [`thread-loop-without-terminated`](#thread-loop-without-terminated) | Thread-Schleife ohne Terminated | Bug | Warnung |
| [`anonymous-thread-not-started`](#anonymous-thread-not-started) | Anonymer Thread nie gestartet | Bug | Warnung |
| [`task-exception-unobserved`](#task-exception-unobserved) | Exception in TTask geht verloren | Code Smell | Hinweis |
| [`parallel-for-shared-write`](#parallel-for-shared-write) | Gemeinsame Variable in TParallel.For geschrieben | Bug | Warnung |
| [`thread-unsafe-increment`](#thread-unsafe-increment) | Zähler im Thread ohne TInterlocked | Bug | Warnung |

<a id="gruppe-database"></a>
### Datenbank

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`dataset-loop-without-next`](#dataset-loop-without-next) | Datenmengen-Schleife ohne Next | Bug | Fehler |
| [`dataset-edit-without-post`](#dataset-edit-without-post) | Edit oder Append ohne Post | Bug | Warnung |
| [`transaction-without-rollback`](#transaction-without-rollback) | Transaktion ohne Rollback | Bug | Warnung |
| [`sql-write-without-where`](#sql-write-without-where) | UPDATE oder DELETE ohne WHERE | Bug | Warnung |
| [`sql-select-star`](#sql-select-star) | SELECT * im Code | Code Smell | Hinweis |

<a id="gruppe-compiler"></a>
### Compiler vorab

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`syntax`](#syntax) | Syntaxfehler | Bug | Fehler |
| [`language-feature`](#language-feature) | Sprachmerkmal einer neueren Delphi-Version | Bug | Warnung |
| [`for-high-to-low`](#for-high-to-low) | for-Schleife zählt mit to abwärts | Bug | Warnung |
| [`deprecated-symbol`](#deprecated-symbol) | Veraltetes oder gebundenes Symbol | Code Smell | Warnung |
| [`signature-mismatch`](#signature-mismatch) | Implementierung weicht von der Deklaration ab | Bug | Fehler |
| [`interface-not-implemented`](#interface-not-implemented) | Interface-Methode fehlt in der Klasse | Bug | Fehler |
| [`uses-unit-not-found`](#uses-unit-not-found) | Unit in uses nicht gefunden | Bug | Fehler |
| [`unresolved-attribute`](#unresolved-attribute) | Attribut nicht gefunden und still ignoriert | Bug | Fehler |
| [`comparison-as-statement`](#comparison-as-statement) | Vergleich statt Zuweisung als Anweisung | Bug | Fehler |
| [`duplicate-case-label`](#duplicate-case-label) | Doppelte case-Marke | Bug | Fehler |
| [`field-after-method`](#field-after-method) | Feld nach Methoden im selben Abschnitt | Bug | Fehler |
| [`overload-directive-missing`](#overload-directive-missing) | Überladung ohne overload oder mit gleicher Signatur | Bug | Fehler |
| [`duplicate-declaration`](#duplicate-declaration) | Bezeichner doppelt deklariert | Bug | Fehler |
| [`conditional-directive-unbalanced`](#conditional-directive-unbalanced) | Bedingte Direktiven unvollständig oder unbekannt | Bug | Fehler |
| [`override-target-missing`](#override-target-missing) | override ohne passende virtuelle Methode | Bug | Fehler |
| [`abstract-class-instantiated`](#abstract-class-instantiated) | Instanz einer Klasse mit abstrakten Methoden | Bug | Warnung |
| [`property-accessor-invalid`](#property-accessor-invalid) | Getter oder Setter einer Property ungültig | Bug | Fehler |
| [`assign-to-property-member`](#assign-to-property-member) | Zuweisung an ein Feld eines Property-Records | Bug | Fehler |
| [`readonly-property-assigned`](#readonly-property-assigned) | Zuweisung an eine Property ohne write | Bug | Fehler |
| [`unit-name-mismatch`](#unit-name-mismatch) | Unit-Name passt nicht zum Dateinamen | Bug | Fehler |
| [`text-after-final-end`](#text-after-final-end) | Text nach dem abschließenden end. | Code Smell | Warnung |
| [`exports-invalid`](#exports-invalid) | exports-Klausel unzulässig | Bug | Fehler |
| [`unit-name-conflict`](#unit-name-conflict) | Unit-Name kollidiert | Bug | Fehler |
| [`implicit-variants-unit`](#implicit-variants-unit) | Variant ohne System.Variants in uses | Code Smell | Hinweis |
| [`file-encoding-unsupported`](#file-encoding-unsupported) | Kodierung oder Zeichen, die der Compiler nicht liest | Bug | Fehler |
| [`anonymous-capture-invalid`](#anonymous-capture-invalid) | Anonyme Methode erfasst, was sie nicht erfassen darf | Bug | Fehler |
| [`operator-declaration-invalid`](#operator-declaration-invalid) | Operator falsch deklariert | Bug | Fehler |
| [`generic-declaration-invalid`](#generic-declaration-invalid) | Generische Deklaration unzulässig | Bug | Fehler |
| [`type-restriction-violated`](#type-restriction-violated) | Sprachregel für Records, Inline und Helfer verletzt | Bug | Fehler |
| [`attribute-usage-invalid`](#attribute-usage-invalid) | Attribut falsch verwendet | Bug | Fehler |
| [`typeinfo-invalid`](#typeinfo-invalid) | TypeInfo oder Default mit unzulässigem Argument | Bug | Fehler |
| [`inherited-constructor-after-try`](#inherited-constructor-after-try) | Geerbter Konstruktor erst im try-Block | Bug | Hinweis |
| [`variant-record-managed-field`](#variant-record-managed-field) | Verwalteter Typ im varianten Teil eines Records | Bug | Fehler |
| [`guid-syntax-invalid`](#guid-syntax-invalid) | GUID mit falscher Schreibweise | Bug | Fehler |
| [`untyped-pointer-refcount`](#untyped-pointer-refcount) | Untypisierter Zeiger umgeht die Referenzzählung | Bug | Warnung |
| [`type-too-large`](#type-too-large) | Typ überschreitet eine Größengrenze | Bug | Fehler |
| [`comparison-always-constant`](#comparison-always-constant) | Vergleich immer wahr oder immer falsch | Bug | Warnung |
| [`constant-initializer-mismatch`](#constant-initializer-mismatch) | Initialisierung einer Konstanten passt nicht | Bug | Fehler |
| [`case-selector-not-ordinal`](#case-selector-not-ordinal) | case oder for ohne ordinalen Typ | Bug | Fehler |
| [`suspicious-string-pointer-cast`](#suspicious-string-pointer-cast) | Zeiger und Zeichenbreite eines Strings passen nicht zusammen | Bug | Warnung |
| [`inaccessible-member`](#inaccessible-member) | Zugriff auf ein nicht sichtbares Mitglied | Bug | Fehler |
| [`unused-private-member`](#unused-private-member) | Privates Mitglied wird nie verwendet | Code Smell | Hinweis |
| [`message-method-invalid`](#message-method-invalid) | message-Methode falsch deklariert | Bug | Fehler |
| [`interface-declaration-invalid`](#interface-declaration-invalid) | Unzulässige Deklaration in einem Interface | Bug | Fehler |
| [`implements-clause-invalid`](#implements-clause-invalid) | implements-Klausel unzulässig | Bug | Fehler |
| [`calling-convention-required`](#calling-convention-required) | Aufrufkonvention passt nicht | Bug | Fehler |
| [`abstract-declaration-invalid`](#abstract-declaration-invalid) | abstract, final oder static falsch kombiniert | Bug | Fehler |
| [`unsatisfied-forward`](#unsatisfied-forward) | Vorwärtsdeklaration nie aufgelöst | Bug | Fehler |
| [`member-hides-ancestor`](#member-hides-ancestor) | Member verdeckt einen Member des Vorfahren | Bug | Warnung |
| [`published-type-invalid`](#published-type-invalid) | Unzulässiges Mitglied im published-Abschnitt | Bug | Fehler |
| [`override-case-mismatch`](#override-case-mismatch) | Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab | Code Smell | Hinweis |
| [`default-property-invalid`](#default-property-invalid) | default-Property falsch deklariert oder fehlt | Bug | Fehler |
| [`property-redeclaration-invalid`](#property-redeclaration-invalid) | Neu deklarierte Property fehlt im Vorfahren | Bug | Fehler |
| [`inline-not-expanded`](#inline-not-expanded) | Inline-Funktion wird nicht eingebettet | Code Smell | Hinweis |
| [`directive-typo`](#directive-typo) | Unbekannte Direktive (Tippfehler) | Bug | Fehler |
| [`constant-expression-error`](#constant-expression-error) | Fehler in einem konstanten Ausdruck | Bug | Fehler |
| [`default-parameter-invalid`](#default-parameter-invalid) | Unzulässiger Standardwert eines Parameters | Bug | Fehler |
| [`signed-unsigned-mix`](#signed-unsigned-mix) | Vorzeichenbehaftet und vorzeichenlos gemischt | Bug | Warnung |
| [`narrowing-assignment`](#narrowing-assignment) | Zuweisung mit möglichem Datenverlust | Bug | Warnung |
| [`typed-constant-modified`](#typed-constant-modified) | Typisierte Konstante verändert | Bug | Warnung |
| [`string-length-limit`](#string-length-limit) | String-Grenze überschritten | Bug | Warnung |
| [`dynamic-array-misuse`](#dynamic-array-misuse) | New, Dispose oder SetLength falsch für dynamische Arrays | Bug | Fehler |
| [`local-routine-as-callback`](#local-routine-as-callback) | Lokale Routine als Prozedurvariable | Bug | Fehler |
| [`hresult-integer-mix`](#hresult-integer-mix) | Integer und HRESULT vertauscht | Bug | Warnung |
| [`invalid-var-argument`](#invalid-var-argument) | Ungültiges Argument für einen var- oder out-Parameter | Bug | Fehler |
| [`condition-not-boolean`](#condition-not-boolean) | Bedingung ist kein Boolean | Bug | Fehler |
| [`for-in-not-enumerable`](#for-in-not-enumerable) | for-in über einen Typ ohne Enumerator | Bug | Fehler |
| [`inherited-abstract-call`](#inherited-abstract-call) | inherited ruft eine abstrakte Methode auf | Bug | Fehler |
| [`generic-constraint-violated`](#generic-constraint-violated) | Typargument verletzt eine Einschränkung | Bug | Fehler |
| [`unresolved-type`](#unresolved-type) | Typ in einer Deklaration nicht gefunden | Bug | Fehler |
| [`class-reference-nonvirtual-constructor`](#class-reference-nonvirtual-constructor) | Konstruktor über Klassenreferenz nicht virtuell | Bug | Warnung |
| [`jump-outside-allowed-scope`](#jump-outside-allowed-scope) | Break, Continue oder Exit an unzulässiger Stelle | Bug | Fehler |
| [`reraise-outside-handler`](#reraise-outside-handler) | raise ohne Argument außerhalb eines Handlers | Bug | Fehler |
| [`label-misuse`](#label-misuse) | Sprungmarke falsch verwendet | Bug | Fehler |
| [`for-variable-misuse`](#for-variable-misuse) | Schleifenvariable verändert oder nicht lokal | Bug | Fehler |
| [`for-variable-after-loop`](#for-variable-after-loop) | Schleifenvariable nach der Schleife gelesen | Bug | Warnung |
| [`argument-count-mismatch`](#argument-count-mismatch) | Falsche Anzahl Argumente | Bug | Fehler |

<a id="gruppe-robustness"></a>
### Robustheit und Muster

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`random-without-randomize`](#random-without-randomize) | Random ohne Randomize | Code Smell | Hinweis |
| [`format-without-settings`](#format-without-settings) | Formatierung abhängig vom Gebietsschema | Code Smell | Hinweis |
| [`null-compare`](#null-compare) | Vergleich mit Null statt VarIsNull oder IsNull | Code Smell | Warnung |
| [`path-concat-without-delimiter`](#path-concat-without-delimiter) | Pfad ohne Trennzeichen zusammengesetzt | Bug | Warnung |
| [`hardcoded-path`](#hardcoded-path) | Fester Dateipfad im Code | Code Smell | Hinweis |
| [`filename-compare-case`](#filename-compare-case) | Dateinamen mit = verglichen | Bug | Hinweis |
| [`initialization-not-finalized`](#initialization-not-finalized) | Beim Start erzeugtes Objekt wird nicht freigegeben | Bug | Warnung |
| [`compiler-warnings-disabled`](#compiler-warnings-disabled) | Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet | Code Smell | Warnung |
| [`dll-export-unsafe`](#dll-export-unsafe) | Exportierte Routine nicht sicher über DLL-Grenzen aufrufbar | Bug | Warnung |
| [`global-formatsettings-modified`](#global-formatsettings-modified) | Globale FormatSettings wird verändert | Bug | Warnung |
| [`ui-call-in-console-or-service`](#ui-call-in-console-or-service) | Dialog in Konsolenprogramm oder Dienst | Bug | Warnung |
| [`load-without-encoding`](#load-without-encoding) | Text laden oder speichern ohne Kodierung | Bug | Warnung |
| [`registry-hklm-write`](#registry-hklm-write) | Schreiben nach HKEY_LOCAL_MACHINE | Bug | Hinweis |

<a id="gruppe-performance"></a>
### Performance

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`string-concat-in-loop`](#string-concat-in-loop) | String-Verkettung in einer Schleife | Code Smell | Hinweis |
| [`loop-invariant-call`](#loop-invariant-call) | Teurer Aufruf in der Schleifenbedingung | Code Smell | Hinweis |
| [`missing-begin-update`](#missing-begin-update) | Hinzufügen in einer Schleife ohne BeginUpdate | Code Smell | Hinweis |
| [`setlength-in-loop`](#setlength-in-loop) | Array wächst in der Schleife um je ein Element | Code Smell | Hinweis |
| [`managed-param-without-const`](#managed-param-without-const) | Verwalteter Parameter ohne const | Code Smell | Hinweis |
| [`case-insensitive-compare`](#case-insensitive-compare) | Vergleich über UpperCase oder LowerCase | Code Smell | Hinweis |

<a id="gruppe-security"></a>
### Sicherheit

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`bidi-control`](#bidi-control) | Bidirektionales Steuerzeichen | Schwachstelle | Fehler |
| [`invisible-char`](#invisible-char) | Unsichtbares Zeichen | Sicherheits-Hotspot | Warnung |
| [`control-char`](#control-char) | Steuerzeichen | Bug | Fehler |
| [`confusable-identifier`](#confusable-identifier) | Verwechselbarer Bezeichner | Sicherheits-Hotspot | Warnung |
| [`security-command-injection`](#security-command-injection) | Befehlsinjektion | Schwachstelle | Warnung |
| [`security-path-traversal`](#security-path-traversal) | Pfad-Traversal | Schwachstelle | Warnung |
| [`security-weak-crypto`](#security-weak-crypto) | Schwache Kryptografie | Sicherheits-Hotspot | Hinweis |
| [`security-tls-verification-disabled`](#security-tls-verification-disabled) | TLS-Zertifikatsprüfung abgeschaltet | Schwachstelle | Warnung |
| [`security-insecure-http`](#security-insecure-http) | Unverschlüsselte http://-URL | Sicherheits-Hotspot | Hinweis |
| [`security-insecure-random`](#security-insecure-random) | Random für sicherheitsrelevante Werte | Sicherheits-Hotspot | Warnung |
| [`security-sql-injection`](#security-sql-injection) | SQL-Text aus zusammengesetzten Werten (SQL-Injection) | Schwachstelle | Warnung |

<a id="gruppe-components"></a>
### Komponenten

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`component-create-without-override`](#component-create-without-override) | Komponentenkonstruktor ohne override | Bug | Warnung |
| [`component-missing-inherited`](#component-missing-inherited) | Komponentenmethode ohne inherited | Bug | Warnung |
| [`component-default-mismatch`](#component-default-mismatch) | default passt nicht zum Konstruktor | Bug | Warnung |
| [`component-missing-free-notification`](#component-missing-free-notification) | Komponentenreferenz ohne FreeNotification | Bug | Warnung |
| [`component-setter-without-invalidate`](#component-setter-without-invalidate) | Setter ohne Invalidate | Code Smell | Hinweis |
| [`component-fixed-pixels`](#component-fixed-pixels) | Feste Pixelwerte | Code Smell | Warnung |
| [`component-hardcoded-color`](#component-hardcoded-color) | Feste Farbe in Paint | Code Smell | Hinweis |
| [`component-palette-icon`](#component-palette-icon) | Registrierte Komponente ohne Palettensymbol | Code Smell | Hinweis |

<a id="gruppe-forms"></a>
### Formulare und Daten

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`form-field-without-object`](#form-field-without-object) | Formularfeld ohne Objekt | Bug | Warnung |
| [`form-object-without-field`](#form-object-without-field) | Formularobjekt ohne Feld | Bug | Warnung |
| [`form-field-type-mismatch`](#form-field-type-mismatch) | Feldtyp weicht vom Formularobjekt ab | Bug | Warnung |
| [`dfm-circular-datasource`](#dfm-circular-datasource) | Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung | Bug | Warnung |
| [`dfm-master-without-fields`](#dfm-master-without-fields) | Master-Detail ohne MasterFields | Bug | Warnung |
| [`dfm-required-field-without-control`](#dfm-required-field-without-control) | Pflichtfeld ohne sichtbares Eingabe-Control | Bug | Warnung |
| [`dfm-control-field-type-mismatch`](#dfm-control-field-type-mismatch) | Datensensitives Control passt nicht zum Feldtyp | Bug | Warnung |
| [`dfm-duplicate-binding`](#dfm-duplicate-binding) | Zwei Controls an demselben Feld | Bug | Warnung |
| [`dfm-property`](#dfm-property) | Komponenten-Property verletzt eine Eigenschaftsregel | Code Smell | Warnung |
| [`foreign-form-control-access`](#foreign-form-control-access) | Zugriff auf Controls eines anderen Formulars | Code Smell | Warnung |
| [`form-resource-missing`](#form-resource-missing) | Formular-Unit ohne {$R *.dfm} | Bug | Fehler |
| [`form-autocreate-and-manual`](#form-autocreate-and-manual) | Formular automatisch und zusätzlich von Hand erzeugt | Bug | Warnung |
| [`inherited-form-handler-without-inherited`](#inherited-form-handler-without-inherited) | Ereignis-Handler im geerbten Formular ohne inherited | Bug | Warnung |
| [`self-free-in-event-handler`](#self-free-in-event-handler) | Formular gibt sich im eigenen Ereignis frei | Bug | Fehler |

<a id="gruppe-architecture"></a>
### Architektur

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`forbidden-uses`](#forbidden-uses) | Verbotene uses-Beziehung | Code Smell | Fehler |
| [`architecture-role-import`](#architecture-role-import) | Import verletzt die Rollenmatrix | Code Smell | Warnung |
| [`architecture-contract-content`](#architecture-contract-content) | Klasse in einer Contract-Unit | Code Smell | Warnung |
| [`forbidden-symbol`](#forbidden-symbol) | Verbotenes Symbol verwendet | Code Smell | Warnung |

<a id="gruppe-style"></a>
### Stil und Metriken

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`unused-local`](#unused-local) | Ungenutzte lokale Variable | Code Smell | Hinweis |
| [`unused-parameter`](#unused-parameter) | Ungenutzter Parameter | Code Smell | Hinweis |
| [`unused-assignment`](#unused-assignment) | Zugewiesener Wert ungenutzt | Code Smell | Hinweis |
| [`file-header`](#file-header) | Dateikopf fehlt oder weicht ab | Code Smell | Hinweis |
| [`hardcoded-string`](#hardcoded-string) | Text im Code statt resourcestring | Code Smell | Hinweis |
| [`bool-compare`](#bool-compare) | Vergleich mit True oder False | Code Smell | Hinweis |
| [`redundant-assigned-free`](#redundant-assigned-free) | Assigned-Prüfung vor Free | Code Smell | Hinweis |
| [`redundant-parens`](#redundant-parens) | Überflüssige Klammern | Code Smell | Hinweis |
| [`redundant-cast`](#redundant-cast) | Überflüssige Typumwandlung | Code Smell | Hinweis |
| [`redundant-begin-end`](#redundant-begin-end) | begin … end um eine einzelne Anweisung | Code Smell | Hinweis |
| [`with-statement`](#with-statement) | with-Anweisung | Code Smell | Hinweis |
| [`metric-method-length`](#metric-method-length) | Methode zu lang | Code Smell | Hinweis |
| [`metric-nesting-depth`](#metric-nesting-depth) | Zu tief verschachtelt | Code Smell | Hinweis |
| [`metric-cyclomatic-complexity`](#metric-cyclomatic-complexity) | Zyklomatische Komplexität zu hoch | Code Smell | Hinweis |
| [`metric-cognitive-complexity`](#metric-cognitive-complexity) | Kognitive Komplexität zu hoch | Code Smell | Hinweis |
| [`metric-parameter-count`](#metric-parameter-count) | Zu viele Parameter | Code Smell | Hinweis |
| [`metric-boolean-operands`](#metric-boolean-operands) | Bedingung mit zu vielen Operanden | Code Smell | Hinweis |
| [`metric-local-count`](#metric-local-count) | Zu viele lokale Variablen | Code Smell | Hinweis |
| [`metric-exit-points`](#metric-exit-points) | Zu viele Ausstiege | Code Smell | Hinweis |
| [`todo-comment`](#todo-comment) | Offener TODO-Kommentar | Code Smell | Hinweis |
| [`unneeded-forward-declaration`](#unneeded-forward-declaration) | Überflüssige Forward-Deklaration | Code Smell | Hinweis |
| [`shadowed-name`](#shadowed-name) | Lokaler Name verdeckt Feld oder Property | Code Smell | Hinweis |
| [`naming-prefix`](#naming-prefix) | Name ohne das Präfix seiner Art | Code Smell | Hinweis |
| [`boolean-assign-if`](#boolean-assign-if) | if, das nur True oder False zuweist | Code Smell | Hinweis |
| [`magic-number`](#magic-number) | Zahl ohne Namen im Code | Code Smell | Hinweis |
| [`line-length`](#line-length) | Zeile zu lang | Code Smell | Hinweis |
| [`metric-class-size`](#metric-class-size) | Klasse mit zu vielen Membern | Code Smell | Hinweis |
| [`metric-unit-length`](#metric-unit-length) | Unit zu lang | Code Smell | Hinweis |
| [`metric-uses-count`](#metric-uses-count) | Zu viele Units im uses | Code Smell | Hinweis |
| [`metric-inheritance-depth`](#metric-inheritance-depth) | Zu tiefe Vererbung | Code Smell | Hinweis |
| [`public-field`](#public-field) | Öffentliches Feld | Code Smell | Hinweis |
| [`legacy-tlist`](#legacy-tlist) | Ungenerische Liste mit Cast | Code Smell | Information |
| [`legacy-stack-queue`](#legacy-stack-queue) | Ungenerischer Stapel oder ungenerische Warteschlange mit Cast | Code Smell | Information |
| [`global-variable`](#global-variable) | Globale Variable im interface | Code Smell | Hinweis |
| [`commented-out-code`](#commented-out-code) | Auskommentierter Code | Code Smell | Hinweis |
| [`default-parameter`](#default-parameter) | Standardparameter statt Überladung | Code Smell | Warnung |
| [`empty-routine`](#empty-routine) | Leere Methode | Code Smell | Hinweis |
| [`write-only-property`](#write-only-property) | Property ohne read | Code Smell | Hinweis |
| [`xmldoc-mismatch`](#xmldoc-mismatch) | XMLDoc passt nicht zur Signatur | Code Smell | Hinweis |
| [`missing-begin-end`](#missing-begin-end) | Bedingung oder Schleife ohne begin … end | Code Smell | Hinweis |
| [`unused-public-member`](#unused-public-member) | Öffentliches Mitglied wird im Projekt nie verwendet | Code Smell | Hinweis |
| [`now-for-elapsed-time`](#now-for-elapsed-time) | Laufzeit mit Now gemessen | Code Smell | Hinweis |
| [`money-as-float`](#money-as-float) | Geldbetrag als Gleitkommazahl | Bug | Hinweis |
| [`string-if-chain`](#string-if-chain) | Lange if-Kette über denselben String | Code Smell | Hinweis |
| [`empty-finally`](#empty-finally) | Leerer finally-Block | Code Smell | Hinweis |
| [`override-only-inherited`](#override-only-inherited) | override ruft nur inherited auf | Code Smell | Hinweis |
| [`inherited-without-ancestor`](#inherited-without-ancestor) | inherited ohne Methode im Vorfahr | Code Smell | Hinweis |
| [`redundant-jump`](#redundant-jump) | Überflüssiges Exit oder Continue | Code Smell | Hinweis |

<a id="gruppe-packages"></a>
### Packages und Tests

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`implicit-package-import`](#implicit-package-import) | Implizit eingebundene Unit | Code Smell | Warnung |
| [`ota-notifier-not-removed`](#ota-notifier-not-removed) | IDE-Notifier ohne RemoveNotifier | Bug | Warnung |
| [`dunitx-test-without-assert`](#dunitx-test-without-assert) | DUnitX-Test ohne Assert | Code Smell | Hinweis |

<a id="gruppe-internal"></a>
### Atlas intern

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`unused-suppression`](#unused-suppression) | Ungenutzte Unterdrückung | Code Smell | Hinweis |
| [`unknown-rule-id`](#unknown-rule-id) | Unbekannte Regelkennung | Code Smell | Hinweis |
| [`unit-too-deep`](#unit-too-deep) | Unit zu tief für die Prüfung | Code Smell | Hinweis |
| [`slash-command`](#slash-command) | Schnellbefehl nicht ausgeführt | Code Smell | Hinweis |

## Regeln

<a id="syntax"></a>
### syntax

**Syntaxfehler** · Bug · Fehler · Gruppe Compiler vorab

Der Quelltext lässt sich nicht lesen. Die Meldung nennt wie der Compiler, was erwartet und was gefunden wurde („';' erwartet, aber 'end' gefunden (wie E2029).“), und trägt den Compilercode: fehlendes ';' (E2066 zwischen Anweisungen, E2029 in Deklarationen), ';' vor else (E2153), offener String (E2052) oder Kommentar mit Startzeile (E2057), Anweisungen im interface-Teil (E2050), Bezeichner nach einem Punkt am Ende (E2372), strict ohne private oder protected (E2375), class vor etwas anderem als einer Routine (E2357), try ohne except oder finally (E2125), for ohne Variable (E2088). Prüfungen am fertigen Baum: procedure mit Ergebnistyp (E2025), Deklaration einer function ohne Ergebnistyp (E2023; die Kurzform der Implementierung ist erlaubt), Wertparameter ohne Typ (E2067), lokale Variable mit Anfangswert (E2195) oder mehrere Variablen mit einem Anfangswert (E2196), Klassen-, Interface- oder Objekttyp im var-Abschnitt (E2060, E2058) oder lokal in einer Routine (E2061, E2059), label im interface-Teil (E2049) und goto auf eine nicht deklarierte Marke (E2031; eine Marke der umgebenden Routine meldet label-misuse als E2093). Nach einem offenen String oder Kommentar fallen die Folgefehler weg, weil der Compiler dort abbricht. Inaktive {$IFDEF}-Zweige werden nicht gemeldet. Korrekturen: ';' vor else entfernen (sicher, auch beim Speichern), ';' ergänzen, String schließen, Kommentar am Ende seiner ersten Zeile schließen.

Entspricht der Compilermeldung `E2023`, `E2025`, `E2029`, `E2031`, `E2049`, `E2050`, `E2052`, `E2057`, `E2058`, `E2059`, `E2060`, `E2061`, `E2066`, `E2067`, `E2088`, `E2125`, `E2153`, `E2195`, `E2196`, `E2357`, `E2372`, `E2375`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
if Gueltig then
  Speichern;
else
  Verwerfen;
```

Richtig:

```pascal
if Gueltig then
  Speichern
else
  Verwerfen;
```

<a id="language-feature"></a>
### language-feature

**Sprachmerkmal einer neueren Delphi-Version** · Bug · Warnung · Gruppe Compiler vorab

Der Code nutzt ein Sprachmerkmal, das der Sprachstand des Projekts noch nicht kennt: Inline-Variable und -Konstante (Delphi 10.3), Managed Record mit class operator Initialize/Finalize (Delphi 10.4), Ziffern-Trennzeichen 1_000 und Binärliteral %1010 (Delphi 11), mehrzeiliger String ''' (Delphi 12), If-Ausdruck, „is not“ und „not in“ (Delphi 13). Der Sprachstand ist die ältere aus delphiVersion und minDelphiVersion in atlas.json: minDelphiVersion nennt die älteste Delphi-Version, mit der das Projekt noch übersetzen muss (z. B. „12“ für Code, den Delphi 12 und 13 übersetzen). Ohne beide Angaben meldet Atlas nichts. Inaktive Zweige {$IF CompilerVersion >= …} bleiben still, so kann Code für mehrere Versionen nebeneinander stehen. Gemeldet im Editor, von --check, check_code und dem Claude-Code-Hook (hook_check). Code-Aktionen und Schnellbefehle erzeugen keine Merkmale über den Sprachstand hinaus.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
// minDelphiVersion "12"
if Sender is not TButton then
  Exit;
```

Richtig:

```pascal
if not (Sender is TButton) then
  Exit;
```

<a id="unused-suppression"></a>
### unused-suppression

**Ungenutzte Unterdrückung** · Code Smell · Hinweis · Gruppe Atlas intern

Ein lsp-ignore-Kommentar unterdrückt keinen Treffer und kann entfernt werden.

Mit Treffer:

```pascal
// lsp-ignore: empty-except
X := 1;
```

Richtig:

```pascal
X := 1;
```

<a id="unknown-rule-id"></a>
### unknown-rule-id

**Unbekannte Regelkennung** · Code Smell · Hinweis · Gruppe Atlas intern

Ein lsp-ignore-Kommentar nennt eine Regelkennung, die es nicht gibt, und unterdrückt deshalb nichts. Die Meldung schlägt die ähnlichste bekannte Kennung vor (Tippfehler); ein solcher Kommentar zählt nicht zusätzlich als unused-suppression.

Mit Treffer:

```pascal
// lsp-ignore: empty-exept
try X; except end;
```

Richtig:

```pascal
// lsp-ignore: empty-except
try X; except end;
```

<a id="unit-too-deep"></a>
### unit-too-deep

**Unit zu tief für die Prüfung** · Code Smell · Hinweis · Gruppe Atlas intern

Der Syntaxbaum der Unit ist mehr als 100000 Ebenen tief; die Prüfregeln laufen für sie nicht. So tiefe Bäume entstehen nur aus Ketten mit ebenso vielen Gliedern wie X := A - B - C - … Der Hinweis markiert die tiefste Stelle; wer die Kette in Teilausdrücke aufteilt, macht die Unit wieder prüfbar.

Mit Treffer:

```pascal
X := A - B - C - D - E; // … 100000 terms
```

Richtig:

```pascal
Part := A - B - C;
X := Part - D - E;
```

<a id="bidi-control"></a>
### bidi-control

**Bidirektionales Steuerzeichen** · Schwachstelle · Fehler · Gruppe Sicherheit

Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source); auch in Formulardateien. Richtungsmarken in RTL-Text nur mit niedriger Konfidenz.

Mit Treffer:

```pascal
if IsAdmin then { U+202E } begin
```

Richtig:

```pascal
if IsAdmin then begin
```

<a id="invisible-char"></a>
### invisible-char

**Unsichtbares Zeichen** · Sicherheits-Hotspot · Warnung · Gruppe Sicherheit

Unsichtbare oder Nullbreiten-Zeichen im Quelltext und in Formulardateien; in Strings und Kommentaren mittlere Konfidenz.

Mit Treffer:

```pascal
Count{U+200B} := 0;
```

Richtig:

```pascal
Count := 0;
```

<a id="control-char"></a>
### control-char

**Steuerzeichen** · Bug · Fehler · Gruppe Sicherheit

NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei; ungültige Bytes mit genauer Zeile und Spalte.

Mit Treffer:

```pascal
S := 'abc{U+0000}';
```

Richtig:

```pascal
S := 'abc' + #0;
```

<a id="confusable-identifier"></a>
### confusable-identifier

**Verwechselbarer Bezeichner** · Sicherheits-Hotspot · Warnung · Gruppe Sicherheit

Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen sind mit anderen verwechselbar.

Mit Treffer:

```pascal
var Pаssword: string; { Cyrillic 'а' }
```

Richtig:

```pascal
var Password: string;
```

<a id="forbidden-uses"></a>
### forbidden-uses

**Verbotene uses-Beziehung** · Code Smell · Fehler · Gruppe Architektur

Ein uses-Eintrag verletzt eine Schichtregel unter "layers" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `layers` | json | `[]` | Schichtregeln: [{"from": Glob, "deny": [Globs], "allow": [Globs]}]. |

Mit Treffer:

```pascal
unit App.Common.Model;
interface
uses Vcl.Forms;
```

Richtig:

```pascal
unit App.Common.Model;
interface
uses System.Classes;
```

<a id="architecture-role-import"></a>
### architecture-role-import

**Import verletzt die Rollenmatrix** · Code Smell · Warnung · Gruppe Architektur

Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus; in atlas.json mit der Option "prefixes" einschalten. Genehmigte Ausnahmen stehen unter "allow" als "Quelle -> Ziel"-Globs.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `prefixes` | string-list | `[]` | Präfixe der Ausgabeartefakte, z. B. "Atlas.Common"; ohne Angabe meldet die Regel nichts. |
| `hostRoles` | string-list | `["Foundation","Core","Shell","Adapters","Platform"]` | Erste Namenssegmente der Host-Units ohne Präfix. |
| `allow` | string-list | `[]` | Genehmigte Ausnahmen "Quelle -> Ziel" (beide Globs). |

Mit Treffer:

```pascal
unit Atlas.Common.Logging.Contract;
interface
uses Atlas.Common.Logging.Providers.Logger;
```

Richtig:

```pascal
unit Atlas.Common.Logging.Contract;
interface
uses System.SysUtils;
```

<a id="architecture-contract-content"></a>
### architecture-contract-content

**Klasse in einer Contract-Unit** · Code Smell · Warnung · Gruppe Architektur

Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option "prefixes" einschalten. Genehmigte Ausnahmen stehen unter "allow" als "Unit.Typ"-Globs.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `prefixes` | string-list | `[]` | Präfixe der Ausgabeartefakte, z. B. "Atlas.Common". |
| `allow` | string-list | `[]` | Genehmigte Ausnahmen "Unit.Typ" als Glob. |

Mit Treffer:

```pascal
unit App.Orders.Contract;
interface
type
  TOrderList = class
  end;
```

Richtig:

```pascal
unit App.Orders.Contract;
interface
type
  IOrderList = interface
  end;
```

<a id="forbidden-symbol"></a>
### forbidden-symbol

**Verbotenes Symbol verwendet** · Code Smell · Warnung · Gruppe Architektur

Eine Liste unter "symbols" in atlas.json verbietet Routinen, Typen, Konstanten, Felder, Properties, Aufzählungswerte oder Bezeichner, jeweils mit Meldung und Ersatz. Verglichen wird über die Namensauflösung, nicht über Text: System.SysUtils.FileExists trifft auch FileExists, aber nicht eine eigene Methode gleichen Namens. Ein Eintrag darf den Namen ab einer Punktgrenze kürzen (TThread.Queue) und * enthalten. Bezeichner aus System ohne Quelltext (Writeln, Halt) gelten als System.<Name>. Ist der linke Teil eines qualifizierten Namens gar nicht auflösbar (Unit nicht indexiert), wird der geschriebene Name mit dem Ende des Eintrags verglichen. Je Eintrag: kind (routine, type, constant, field, property, enumValue, identifier = nach Namen ohne Auflösung), message, replacement, severity, units (Muster der Unit-Namen, "!" schließt aus), firstArgument (nur mit diesem ersten Argument, z. B. nil) und allowFirstArgument (erlaubt mit diesem ersten Argument, z. B. ErrOutput); beide vergleichen den Text des Arguments oder den Namen seines Typs (TextFile). Standard aus und ohne Liste stumm; im Profil strict an. Sicherheit hoch. Schnellkorrektur: durch den konfigurierten Ersatz ersetzen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `symbols` | object-list | `[]` | Tabelle der verbotenen Symbole, ein Objekt je Eintrag: name (qualifiziert, * erlaubt), kind (routine, type, constant, field, property, enumValue oder identifier), message, replacement, severity, units (Muster, ! schließt aus), firstArgument und allowFirstArgument (Texte oder Typnamen des Arguments). |

Mit Treffer:

```pascal
// atlas.json: "forbidden-symbol": {"symbols": [{"name": "System.Write*", "kind": "routine", "message": "Only via ILogger"}]}
procedure TImport.Report(const AText: string);
begin
  Writeln(AText);
end;
```

Richtig:

```pascal
procedure TImport.Report(const AText: string);
begin
  FLogger.Info(AText);
end;
```

<a id="thread-vcl-access"></a>
### thread-vcl-access

**VCL-Zugriff aus einem Thread** · Bug · Warnung · Gruppe Threads

TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist nicht threadsicher.

Mit Treffer:

```pascal
procedure TWorker.Execute;
begin
  Application.Title := 'Done';
end;
```

Richtig:

```pascal
procedure TWorker.Execute;
begin
  TThread.Queue(nil, procedure begin Application.Title := 'Done' end);
end;
```

<a id="lock-without-finally"></a>
### lock-without-finally

**Sperre ohne try/finally** · Bug · Warnung · Gruppe Threads

Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPairs) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `lockPairs` | json | `[]` | Weitere Sperrpaare als [["Sperren", "Freigeben"]]. |

Mit Treffer:

```pascal
CS.Enter;
DoWork;
CS.Leave;
```

Richtig:

```pascal
CS.Enter;
try
  DoWork;
finally
  CS.Leave;
end;
```

<a id="thread-use-after-free-on-terminate"></a>
### thread-use-after-free-on-terminate

**Thread nach dem Start mit FreeOnTerminate benutzt** · Bug · Warnung · Gruppe Threads

Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu.

Mit Treffer:

```pascal
T.FreeOnTerminate := True;
T.Start;
Log(T.ThreadID);
```

Richtig:

```pascal
Log(T.ThreadID);
T.FreeOnTerminate := True;
T.Start;
```

<a id="thread-free-with-free-on-terminate"></a>
### thread-free-with-free-on-terminate

**Free auf einem Thread mit FreeOnTerminate** · Bug · Fehler · Gruppe Threads

Free auf einem Thread mit FreeOnTerminate := True gibt ihn doppelt frei.

Mit Treffer:

```pascal
T.FreeOnTerminate := True;
T.Start;
T.Free;
```

Richtig:

```pascal
T.FreeOnTerminate := True;
T.Start;
```

<a id="synchronize-in-destructor"></a>
### synchronize-in-destructor

**Synchronize im Destruktor eines Threads** · Bug · Warnung · Gruppe Threads

Synchronize im Destruktor eines TThread-Nachfahren (oder in einer Methode, die er aufruft) verklemmt sich: Der Hauptthread wartet in WaitFor, der Thread auf Synchronize.

Mit Treffer:

```pascal
destructor TWorker.Destroy;
begin
  Synchronize(Notify);
  inherited;
end;
```

Richtig:

```pascal
destructor TWorker.Destroy;
begin
  inherited;
end;
```

<a id="thread-resume-suspend"></a>
### thread-resume-suspend

**Veraltetes TThread.Resume/Suspend** · Code Smell · Warnung · Gruppe Threads

TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten; Suspend hat keinen sicheren Ersatz, stattdessen mit einem Ereignis warten.

Mit Treffer:

```pascal
FWorker.Resume;
```

Richtig:

```pascal
FWorker.Start;
```

<a id="result-not-set"></a>
### result-not-set

**Funktionsergebnis eventuell nicht gesetzt** · Bug · Warnung · Gruppe Fehler finden

Ein Pfad durch die Funktion endet, ohne Result zuzuweisen. Der Aufrufer liest dann einen undefinierten Wert.

Mit Treffer:

```pascal
function Find: Integer;
begin
  if Ok then
    Result := 1;
end;
```

Richtig:

```pascal
function Find: Integer;
begin
  Result := 0;
  if Ok then
    Result := 1;
end;
```

<a id="possibly-uninitialized"></a>
### possibly-uninitialized

**Variable eventuell nicht initialisiert** · Bug · Warnung · Gruppe Fehler finden

Eine lokale Variable wird auf einem Pfad gelesen, auf dem ihr nie ein Wert zugewiesen wurde.

Mit Treffer:

```pascal
var I: Integer;
begin
  if Ok then
    I := 1;
  Writeln(I);
end;
```

Richtig:

```pascal
var I: Integer;
begin
  I := 0;
  if Ok then
    I := 1;
  Writeln(I);
end;
```

<a id="unreachable-code"></a>
### unreachable-code

**Unerreichbarer Code** · Bug · Warnung · Gruppe Fehler finden

Eine Anweisung nach Exit, raise, Abort, Halt, Break, Continue oder goto wird nie ausgeführt. Meist ein Rest oder ein falsch gesetzter Sprung. Gemeldet wird nur die erste Anweisung eines unerreichbaren Abschnitts.

Mit Treffer:

```pascal
procedure Save;
begin
  Exit;
  Store;
end;
```

Richtig:

```pascal
procedure Save;
begin
  if not Ready then
    Exit;
  Store;
end;
```

<a id="unused-local"></a>
### unused-local

**Ungenutzte lokale Variable** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `[]` | Namensmuster, die nie gemeldet werden (* und ?). |

Mit Treffer:

```pascal
procedure Foo;
var
  I, Count: Integer;
begin
  I := 1;
  Bar(I);
end;
```

Richtig:

```pascal
procedure Foo;
var
  I: Integer;
begin
  I := 1;
  Bar(I);
end;
```

<a id="unused-parameter"></a>
### unused-parameter

**Ungenutzter Parameter** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen und Callbacks.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `[]` | Namensmuster, die nie gemeldet werden (* und ?). |

Mit Treffer:

```pascal
function Twice(A, B: Integer): Integer;
begin
  Result := 2 * A;
end;
```

Richtig:

```pascal
function Twice(A: Integer): Integer;
begin
  Result := 2 * A;
end;
```

<a id="unused-assignment"></a>
### unused-assignment

**Zugewiesener Wert ungenutzt** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077. Variablen mit Interface-Typ sind ausgenommen: Die Zuweisung hält oder gibt eine Referenz frei (Bereichswächter, Writer := nil).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `[]` | Namensmuster, die nie gemeldet werden (* und ?). |

Mit Treffer:

```pascal
procedure Foo;
var
  I: Integer;
begin
  I := 0;
  I := Calc;
  Bar(I);
end;
```

Richtig:

```pascal
procedure Foo;
var
  I: Integer;
begin
  I := Calc;
  Bar(I);
end;
```

<a id="duplicate-assignment"></a>
### duplicate-assignment

**Feld oder Property wird zweimal gesetzt** · Bug · Warnung · Gruppe Fehler finden

Dasselbe Feld oder dieselbe Property (Panel.Left, Self.FWert, P^.X) bekommt zweimal hintereinander einen Wert, ohne dass dazwischen gelesen oder etwas aufgerufen wird; meist sollte die zweite Zeile ein anderes Ziel haben (Left/Top). Dazwischen dürfen nur Zuweisungen an andere Objekte stehen, deren Werte nichts aufrufen und das Ziel nicht nennen; der zweite Wert darf das Ziel nicht lesen. Lokale Variablen deckt unused-assignment ab, Ziele mit Index oder Aufruf zählen nicht. Still beim Wechsel False/True (stößt oft etwas an, etwa Active), bei einer zweiten Zuweisung, die nur unter einer weiteren Bedingung übersetzt wird ({$IFDEF DEBUG}), bei verschiedenen Zweigen desselben {$IFDEF} und bei Properties aus allowProperties. Fehlt das Gegenstück (Left/Top, Width/Height …) in der Folge, nennt die Meldung es als Vermutung. Konfidenz hoch. Keine Schnellkorrektur; Sprung zur ersten Zuweisung.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowProperties` | string-list | `["Visible","Enabled"]` | Properties, bei denen doppeltes Setzen gewollt sein kann (Setter mit Nebenwirkung), Muster mit * und ?. |

Mit Treffer:

```pascal
Panel.Left := 8;
Panel.Left := 40;
Panel.Width := 200;
```

Richtig:

```pascal
Panel.Left := 8;
Panel.Top := 40;
Panel.Width := 200;
```

<a id="declared-not-implemented"></a>
### declared-not-implemented

**Deklariert, aber nicht implementiert** · Bug · Fehler · Gruppe Fehler finden

Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065). Einen Rumpf gleichen Namens mit anderem Kopf meldet stattdessen signature-mismatch.

Mit Treffer:

```pascal
type
  TFoo = class
    procedure Run;
  end;

implementation

end.
```

Richtig:

```pascal
type
  TFoo = class
    procedure Run;
  end;

implementation

procedure TFoo.Run;
begin
end;

end.
```

<a id="implemented-not-declared"></a>
### implemented-not-declared

**Implementiert, aber nicht deklariert** · Bug · Fehler · Gruppe Fehler finden

Ein Methodenrumpf TFoo.Bar hat keine Deklaration dieses Namens im Typ. Eine gleichnamige Deklaration mit anderem Kopf meldet stattdessen signature-mismatch.

Mit Treffer:

```pascal
type
  TFoo = class
  end;

implementation

procedure TFoo.Run;
begin
end;
```

Richtig:

```pascal
type
  TFoo = class
  private
    procedure Run;
  end;

implementation

procedure TFoo.Run;
begin
end;
```

<a id="destroy-without-override"></a>
### destroy-without-override

**Destroy ohne override** · Bug · Warnung · Gruppe Fehler finden

Ein destructor Destroy ist ohne override deklariert. Free ruft TObject.Destroy auf, dieser Destruktor läuft also nie.

Mit Treffer:

```pascal
type
  TFoo = class
    destructor Destroy;
  end;
```

Richtig:

```pascal
type
  TFoo = class
    destructor Destroy; override;
  end;
```

<a id="setter-recursion"></a>
### setter-recursion

**Setter oder Getter ruft sich selbst auf** · Bug · Fehler · Gruppe Fehler finden

Ein Setter weist an die eigene Property zu (Name := Value in SetName) oder ein Getter liest sie (Result := Name in GetName). Das ergibt eine Endlosrekursion und einen Stapelüberlauf zur Laufzeit; der Compiler schweigt. Schnellkorrektur: das Feld verwenden (das Feld aus der Property-Deklaration, sonst F und der Name, wenn die Klasse es hat). Früher recursive-property-accessor; Einstellungen und Unterdrückungen mit der alten Kennung wirken weiter.

Mit Treffer:

```pascal
procedure TKunde.SetName(const Value: string);
begin
  if Name <> Value then
    Name := Value;
end;
```

Richtig:

```pascal
procedure TKunde.SetName(const Value: string);
begin
  if FName <> Value then
    FName := Value;
end;
```

<a id="component-create-without-override"></a>
### component-create-without-override

**Komponentenkonstruktor ohne override** · Bug · Warnung · Gruppe Komponenten

Ein TComponent-Nachfahre deklariert constructor Create(AOwner: TComponent) ohne override. Beim Laden aus der Formulardatei wird der virtuelle Konstruktor benutzt und dieser übergangen.

Mit Treffer:

```pascal
type
  TMyPanel = class(TCustomPanel)
    constructor Create(AOwner: TComponent);
  end;
```

Richtig:

```pascal
type
  TMyPanel = class(TCustomPanel)
    constructor Create(AOwner: TComponent); override;
  end;
```

<a id="hides-virtual"></a>
### hides-virtual

**Methode verdeckt virtuelle Methode** · Bug · Warnung · Gruppe Fehler finden

Eine Methode heißt wie eine virtuelle Methode eines Vorfahren, überschreibt sie aber weder noch führt sie sie neu ein (Compilerwarnung W1010).

Mit Treffer:

```pascal
type
  TBase = class
    procedure Run; virtual;
  end;
  TFoo = class(TBase)
    procedure Run;
  end;
```

Richtig:

```pascal
type
  TBase = class
    procedure Run; virtual;
  end;
  TFoo = class(TBase)
    procedure Run; override;
  end;
```

<a id="virtual-instead-of-override"></a>
### virtual-instead-of-override

**virtual statt override** · Bug · Warnung · Gruppe Fehler finden

Ein Nachfahre deklariert eine Methode als virtual, obwohl der Vorfahr schon eine virtuelle Methode mit derselben Signatur hat; das beginnt eine neue Kette statt zu überschreiben.

Mit Treffer:

```pascal
type
  TFoo = class(TBase)
    procedure Run; virtual;
  end;
```

Richtig:

```pascal
type
  TFoo = class(TBase)
    procedure Run; override;
  end;
```

<a id="captured-loop-variable"></a>
### captured-loop-variable

**Erfasste Schleifenvariable** · Bug · Warnung · Gruppe Fehler finden

Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `deferredApis` | string-list | `[]` | Weitere verzögerte APIs (zusätzlich zu TThread.Queue, TTask.Run u. a.). |

Mit Treffer:

```pascal
for S in List do
  TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);
```

Richtig:

```pascal
function CaptureS(const AValue: string): TProc;
begin
  Result := procedure begin Memo1.Lines.Add(AValue); end;
end;
...
for S in List do
  TThread.Queue(nil, CaptureS(S));
```

<a id="component-missing-inherited"></a>
### component-missing-inherited

**Komponentenmethode ohne inherited** · Bug · Warnung · Gruppe Komponenten

Ein überschriebenes Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy oder Paint einer Komponente ruft inherited nicht auf; die VCL überspringt dann ihre eigene Arbeit. Bei Paint ist die Konfidenz niedrig, weil TCustomControl.Paint nur den Rahmen im Designer zeichnet.

Mit Treffer:

```pascal
procedure TMyControl.Loaded;
begin
  UpdateLayout;
end;
```

Richtig:

```pascal
procedure TMyControl.Loaded;
begin
  inherited;
  UpdateLayout;
end;
```

<a id="component-default-mismatch"></a>
### component-default-mismatch

**default passt nicht zum Konstruktor** · Bug · Warnung · Gruppe Komponenten

Eine Eigenschaft gibt einen default-Wert an, der Konstruktor setzt das Feld aber auf ein anderes Literal. Werte gleich default speichert die DFM nicht, deshalb wird die Eigenschaft falsch geladen.

Mit Treffer:

```pascal
property Size: Integer read FSize write FSize default 5;
...
FSize := 10;
```

Richtig:

```pascal
property Size: Integer read FSize write FSize default 10;
...
FSize := 10;
```

<a id="component-missing-free-notification"></a>
### component-missing-free-notification

**Komponentenreferenz ohne FreeNotification** · Bug · Warnung · Gruppe Komponenten

Eine Eigenschaft verweist auf eine andere Komponente, ihr Setter ruft aber FreeNotification nicht auf. Wird die andere Komponente freigegeben, bleibt ein ungültiger Zeiger zurück. Im Konstruktor erzeugte Unterkomponenten sind ausgenommen.

Mit Treffer:

```pascal
procedure TMyControl.SetLink(const Value: TControl);
begin
  FLink := Value;
end;
```

Richtig:

```pascal
procedure TMyControl.SetLink(const Value: TControl);
begin
  FLink := Value;
  if Value <> nil then Value.FreeNotification(Self);
end;
```

<a id="component-setter-without-invalidate"></a>
### component-setter-without-invalidate

**Setter ohne Invalidate** · Code Smell · Hinweis · Gruppe Komponenten

Ein Setter ändert ein Feld, das Paint liest, ruft aber weder Invalidate noch Repaint, Refresh oder Changed auf. Das Steuerelement zeigt weiter den alten Zustand.

Mit Treffer:

```pascal
procedure TMyControl.SetColor(const Value: TColor);
begin
  FColor := Value;
end;
```

Richtig:

```pascal
procedure TMyControl.SetColor(const Value: TColor);
begin
  FColor := Value;
  Invalidate;
end;
```

<a id="component-fixed-pixels"></a>
### component-fixed-pixels

**Feste Pixelwerte** · Code Smell · Warnung · Gruppe Komponenten

Paint oder Resize verwenden feste Pixelwerte, die über 96 dpi zu klein sind. Werte über ScaleValue oder MulDiv, 0, 1 und -1 sowie Faktoren von Multiplikationen und Divisionen werden nicht gemeldet.

Mit Treffer:

```pascal
Canvas.FillRect(Rect(0, 0, 16, 16));
```

Richtig:

```pascal
Canvas.FillRect(Rect(0, 0, ScaleValue(16), ScaleValue(16)));
```

<a id="component-hardcoded-color"></a>
### component-hardcoded-color

**Feste Farbe in Paint** · Code Smell · Hinweis · Gruppe Komponenten

Paint verwendet ein RGB-Literal, eine $00BBGGRR-Konstante oder einen TColor-Cast. Solche Farben ignorieren VCL-Styles; Systemfarben wie clBtnFace sind in Ordnung.

Mit Treffer:

```pascal
Canvas.Brush.Color := $00FF8000;
```

Richtig:

```pascal
Canvas.Brush.Color := StyleServices.GetSystemColor(clHighlight);
```

<a id="form-field-without-object"></a>
### form-field-without-object

**Formularfeld ohne Objekt** · Bug · Warnung · Gruppe Formulare und Daten

Ein published-Komponentenfeld der Formularklasse hat kein Objekt in der .dfm/.fmx neben der Unit. Nach dem Laden bleibt das Feld nil. Felder außerhalb von published werden nicht geprüft.

Mit Treffer:

```pascal
Edit1: TEdit;  // object Edit1 was deleted from the form
```

Richtig:

```pascal
// remove the field or restore the object
```

<a id="form-object-without-field"></a>
### form-object-without-field

**Formularobjekt ohne Feld** · Bug · Warnung · Gruppe Formulare und Daten

Ein Objekt der Formulardatei hat kein Feld in der Formularklasse. Geerbte Objekte, Objekte in inline-Frames, namenlose Komponenten und Collection-Einträge werden übergangen. Die Korrektur ergänzt das Feld.

Mit Treffer:

```pascal
object Button2: TButton  // no Button2 in TForm1
```

Richtig:

```pascal
Button2: TButton;
```

<a id="form-field-type-mismatch"></a>
### form-field-type-mismatch

**Feldtyp weicht vom Formularobjekt ab** · Bug · Warnung · Gruppe Formulare und Daten

Der Typ des Felds weicht von der Klasse des Objekts in der Formulardatei ab. Ohne Quelltext der Klasse aus der Formulardatei wird nicht verglichen. Die Korrektur ändert den Feldtyp.

Mit Treffer:

```pascal
Edit1: TEdit;  // object Edit1: TMaskEdit
```

Richtig:

```pascal
Edit1: TMaskEdit;
```

<a id="security-command-injection"></a>
### security-command-injection

**Befehlsinjektion** · Schwachstelle · Warnung · Gruppe Sicherheit

ShellExecute, ShellExecuteEx, CreateProcess oder WinExec erhält ein Argument, das mit +, Format oder Concat aus nicht konstanten Werten zusammengesetzt ist. Eingaben könnten weitere Befehle einschleusen. Ohne Datenflussanalyse wird nur dieses einfache Muster erkannt (mittlere Konfidenz).

Mit Treffer:

```pascal
ShellExecute(0, 'open', PChar('cmd /c ' + Edit1.Text), nil, nil, SW_SHOW);
```

Richtig:

```pascal
ShellExecute(0, 'open', 'tool.exe', PChar(QuotedArgument), nil, SW_SHOW);  // validated
```

<a id="security-path-traversal"></a>
### security-path-traversal

**Pfad-Traversal** · Schwachstelle · Warnung · Gruppe Sicherheit

Ein Dateizugriff (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) verwendet einen Pfad aus Eingabedaten (Text, ParamStr, Request) ohne Prüfung über TPath.GetFullPath. Experimentell, bis die Datenflussanalyse verfügbar ist.

Mit Treffer:

```pascal
List.LoadFromFile('C:\Data\' + Edit1.Text);
```

Richtig:

```pascal
Path := TPath.GetFullPath(TPath.Combine(Root, Edit1.Text));  // then check it starts with Root
```

<a id="security-weak-crypto"></a>
### security-weak-crypto

**Schwache Kryptografie** · Sicherheits-Hotspot · Hinweis · Gruppe Sicherheit

MD5, SHA-1, DES oder RC4 wird verwendet. Für Prüfsummen ist das in Ordnung, für Kennwörter und Signaturen nicht. Niedrige Konfidenz, mittlere, wenn die Anweisung ein Kennwort, Geheimnis oder eine Signatur nennt.

Mit Treffer:

```pascal
Stored := THashSHA1.GetHashString(PasswordText);
```

Richtig:

```pascal
Stored := THashSHA2.GetHashString(Salt + PasswordText);
```

<a id="security-tls-verification-disabled"></a>
### security-tls-verification-disabled

**TLS-Zertifikatsprüfung abgeschaltet** · Schwachstelle · Warnung · Gruppe Sicherheit

Indy SSLOptions.VerifyMode := [], ein OnVerifyPeer-Handler, der immer True liefert, oder ein ValidateServerCertificate-Handler, der Accepted := True ohne Prüfung setzt.

Mit Treffer:

```pascal
IdSSL.SSLOptions.VerifyMode := [];
```

Richtig:

```pascal
IdSSL.SSLOptions.VerifyMode := [sslvrfPeer];
```

<a id="security-insecure-http"></a>
### security-insecure-http

**Unverschlüsselte http://-URL** · Sicherheits-Hotspot · Hinweis · Gruppe Sicherheit

Ein String enthält eine http://-URL. XML-Namensräume und Schema-URIs, Kommentare sowie localhost, 127.0.0.1 und [::1] sind ausgenommen. Die Korrektur ersetzt http:// durch https://.

Mit Treffer:

```pascal
Client.Get('http://api.example.com/data');
```

Richtig:

```pascal
Client.Get('https://api.example.com/data');
```

<a id="security-insecure-random"></a>
### security-insecure-random

**Random für sicherheitsrelevante Werte** · Sicherheits-Hotspot · Warnung · Gruppe Sicherheit

Random wird einem Token, Kennwort, Salt, Nonce oder Schlüssel zugewiesen. Random ist vorhersagbar; einen kryptografischen Zufallsgenerator verwenden. Fehlendes Randomize behandelt #153.

Mit Treffer:

```pascal
Token := IntToStr(Random(MaxInt));
```

Richtig:

```pascal
Token := TNetEncoding.Base64URL.EncodeBytesToString(CryptoRandomBytes(32));
```

<a id="dfm-circular-datasource"></a>
### dfm-circular-datasource

**Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung** · Bug · Warnung · Gruppe Formulare und Daten

MasterSource/DataSource-Verknüpfungen der Formulardatei bilden einen Kreis (tblA → dsB → tblB → dsA → tblA). Das Öffnen der Datasets läuft in eine Rekursion oder zeigt keine stimmigen Daten.

Mit Treffer:

```pascal
tblA.MasterSource = dsB; tblB.MasterSource = dsA
```

Richtig:

```pascal
tblB.MasterSource = dsA  // tblA has no master
```

<a id="dfm-master-without-fields"></a>
### dfm-master-without-fields

**Master-Detail ohne MasterFields** · Bug · Warnung · Gruppe Formulare und Daten

Ein Dataset hat MasterSource, aber keine MasterFields. Das Detail wird nicht gefiltert und zeigt alle Datensätze.

Mit Treffer:

```pascal
MasterSource = dsKunden
```

Richtig:

```pascal
MasterSource = dsKunden; MasterFields = 'KundenID'
```

<a id="dfm-required-field-without-control"></a>
### dfm-required-field-without-control

**Pflichtfeld ohne sichtbares Eingabe-Control** · Bug · Warnung · Gruppe Formulare und Daten

Ein persistentes Feld mit Required = True ist an kein sichtbares datensensitives Control gebunden (ein Gitter ohne DataField zählt für alle Felder). Der Anwender kann es nicht füllen, Post schlägt fehl.

Mit Treffer:

```pascal
tblKundenName: Required = True, no TDBEdit for Name
```

Richtig:

```pascal
edName: TDBEdit; DataSource = dsKunden; DataField = 'Name'
```

<a id="dfm-control-field-type-mismatch"></a>
### dfm-control-field-type-mismatch

**Datensensitives Control passt nicht zum Feldtyp** · Bug · Warnung · Gruppe Formulare und Daten

Das Control passt nicht zum persistenten Feld, z. B. TDBEdit an einem TBooleanField oder Blob-Feld, TDBImage an einem Feld ohne Grafik.

Mit Treffer:

```pascal
edAktiv: TDBEdit; DataField = 'Aktiv'  // TBooleanField
```

Richtig:

```pascal
cbAktiv: TDBCheckBox; DataField = 'Aktiv'
```

<a id="dfm-duplicate-binding"></a>
### dfm-duplicate-binding

**Zwei Controls an demselben Feld** · Bug · Warnung · Gruppe Formulare und Daten

Zwei Eingabe-Controls nutzen dieselbe DataSource und dasselbe DataField. Meist ein Kopierfehler. Anzeige-Controls (TDBText, TDBImage) zählen nicht.

Mit Treffer:

```pascal
ed1, ed2: DataSource = dsA; DataField = 'Name'
```

Richtig:

```pascal
ed1: DataField = 'Name'; ed2: DataField = 'Vorname'
```

<a id="dfm-property"></a>
### dfm-property

**Komponenten-Property verletzt eine Eigenschaftsregel** · Code Smell · Warnung · Gruppe Formulare und Daten

Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zählen mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt. Die Schnellkorrektur setzt den Wert in der Formulardatei (fix: auto auch mit source.fixAll); der Befehl "Eigenschaftsregeln anwenden" korrigiert ein Formular, das Projekt oder die Gruppe mit Vorschau.

Mit Treffer:

```pascal
// dfmPropertyRules: TLabel.Transparent = True
object Label1: TLabel
  Caption = 'Name'
end
```

Richtig:

```pascal
object Label1: TLabel
  Caption = 'Name'
  Transparent = True
end
```

<a id="foreign-form-control-access"></a>
### foreign-form-control-access

**Zugriff auf Controls eines anderen Formulars** · Code Smell · Warnung · Gruppe Formulare und Daten

Code greift über die globale Variable auf ein Feld eines Formulars oder Frames aus einer anderen Unit zu (Form2.Edit1.Text). Das koppelt die Units eng; besser eine Methode oder Property des Formulars nutzen.

Mit Treffer:

```pascal
Form2.Edit1.Text := 'x';
```

Richtig:

```pascal
Form2.Kundenname := 'x';
```

<a id="security-sql-injection"></a>
### security-sql-injection

**SQL-Text aus zusammengesetzten Werten (SQL-Injection)** · Schwachstelle · Warnung · Gruppe Sicherheit

SQL.Text, SQL.Add, CommandText, ExecSQL oder Open erhalten Text, der per + oder Format aus Nicht-Konstanten zusammengesetzt ist. Benutzereingaben könnten SQL einschleusen. Parameter verwenden (:Name, ParamByName). Konstanten, resourcestrings, IntToStr und QuotedStr zählen nicht; Benutzereingaben (TEdit.Text, TMemo.Lines) heben die Konfidenz auf hoch.

Mit Treffer:

```pascal
Q.SQL.Text := 'select * from K where N = ''' + Edit1.Text + '''';
```

Richtig:

```pascal
Q.SQL.Text := 'select * from K where N = :N';
Q.ParamByName('N').AsString := Edit1.Text;
```

<a id="slash-command"></a>
### slash-command

**Schnellbefehl nicht ausgeführt** · Code Smell · Hinweis · Gruppe Atlas intern

Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nicht. Die Meldung nennt den Grund. "/ignore regel" meldet sie auch, wenn diese Regel in der Zeile darunter nichts findet.

Mit Treffer:

```pascal
/gibtsnicht X
```

Richtig:

```pascal
/uses System.Classes
```

<a id="empty-except"></a>
### empty-except

**Leerer except-Block** · Code Smell · Warnung · Gruppe Exceptions

Ein except-Block ohne Anweisung verschluckt jede Ausnahme. Ein Block, der nur einen Kommentar enthält, gilt als begründet und wird nicht gemeldet.

Mit Treffer:

```pascal
try
  Save;
except
end;
```

Richtig:

```pascal
try
  Save;
except
  on E: EInOutError do
    Log(E.Message);
end;
```

<a id="interface-guid"></a>
### interface-guid

**Interface ohne GUID** · Bug · Warnung · Gruppe Fehler finden

Ein Interface deklariert keine GUID. Supports, as und QueryInterface brauchen eine. Die Konfidenz ist hoch, wenn das Interface in derselben Datei damit verwendet wird, sonst niedrig. Die Schnellkorrektur fügt eine neue GUID ein.

Mit Treffer:

```pascal
type
  ISaver = interface
    procedure Save;
  end;
```

Richtig:

```pascal
type
  ISaver = interface
    ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
    procedure Save;
  end;
```

<a id="duplicate-interface-guid"></a>
### duplicate-interface-guid

**Zwei Interfaces mit derselben GUID** · Bug · Fehler · Gruppe Fehler finden

Zwei Interfaces der Datei deklarieren dieselbe GUID, meist nach dem Kopieren einer Deklaration. Supports und as verwechseln sie dann. Die Schnellkorrektur erzeugt eine neue GUID.

Mit Treffer:

```pascal
ILoader = interface
  ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
end;
ISaver = interface
  ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
end;
```

Richtig:

```pascal
ILoader = interface
  ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
end;
ISaver = interface
  ['{0B9E4F21-7C6D-4A3E-8F15-2D9C7B6A4E31}']
end;
```

<a id="file-header"></a>
### file-header

**Dateikopf fehlt oder weicht ab** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Datei beginnt nicht mit dem Kopf aus der Regeloption "template". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `template` | string | `""` | Erwarteter Dateikopf; Platzhalter wie dokumentiert. |

Mit Treffer:

```pascal
unit Tools;
```

Richtig:

```pascal
// Copyright (c) Example GmbH
unit Tools;
```

<a id="hardcoded-string"></a>
### hardcoded-string

**Text im Code statt resourcestring** · Code Smell · Hinweis · Gruppe Stil und Metriken

In einer Anweisung steht ein String mit Wörtern für Menschen. In einen resourcestring auslagern, damit er übersetzt werden kann. Standardmäßig aus, niedrige Konfidenz.

Mit Treffer:

```pascal
ShowMessage('File not found');
```

Richtig:

```pascal
resourcestring
  SFileNotFound = 'File not found';
...
ShowMessage(SFileNotFound);
```

<a id="self-assignment"></a>
### self-assignment

**Zuweisung an sich selbst** · Bug · Warnung · Gruppe Fehler finden

Einer Variablen, einem Feld oder einer Property wird der eigene Wert zugewiesen. Gemeint ist meist ein anderer Wert, etwa ein Parameter oder ein anderes Feld. Verdeckt ein Parameter oder eine lokale Variable ein gleichnamiges Feld (Name := Name), bietet Atlas Self.Name := Name als Korrektur an.

Mit Treffer:

```pascal
FName := FName;
```

Richtig:

```pascal
FName := AName;
```

<a id="for-high-to-low"></a>
### for-high-to-low

**for-Schleife zählt mit to abwärts** · Bug · Warnung · Gruppe Compiler vorab

Die Schleife beginnt beim oberen Wert (High, Count - 1) und endet beim unteren, verwendet aber to. Sie läuft nie; gemeint war downto. Ebenso Schleifen mit konstanten Grenzen, die nie laufen, etwa for I := 10 to 1, auch mit Vorzeichen, Hex- oder Zeichenliteralen (wie H2135). Gleiche Grenzen, Ausdrücke, benannte Konstanten und aufsteigende Grenzen bleiben still. Korrektur: to durch downto ersetzen.

Entspricht der Compilermeldung `H2135`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
for I := 10 to 1 do
  Countdown(I);
```

Richtig:

```pascal
for I := 10 downto 1 do
  Countdown(I);
```

<a id="exception-not-raised"></a>
### exception-not-raised

**Exception erzeugt, aber nicht ausgelöst** · Bug · Warnung · Gruppe Fehler finden

Ein Exception-Objekt wird als eigene Anweisung erzeugt. Ohne raise passiert nichts, und das Objekt bleibt als Speicherleck zurück.

Mit Treffer:

```pascal
if X = nil then
  EArgumentException.Create('X missing');
```

Richtig:

```pascal
if X = nil then
  raise EArgumentException.Create('X missing');
```

<a id="assert-side-effect"></a>
### assert-side-effect

**Assert mit Seiteneffekt** · Bug · Warnung · Gruppe Fehler finden

Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den ganzen Aufruf samt Seiteneffekt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `mutatingMethods` | string-list | `["Add","Delete","Remove","Extract","Clear","Insert"]` | Methoden, die ihr Objekt verändern. |

Mit Treffer:

```pascal
Assert(List.Remove(X) >= 0);
```

Richtig:

```pascal
Index := List.Remove(X);
Assert(Index >= 0);
```

<a id="ifthen-side-effect"></a>
### ifthen-side-effect

**IfThen wertet beide Zweige aus** · Bug · Warnung · Gruppe Fehler finden

IfThen ist eine Funktion: Beide Zweige werden vor dem Aufruf ausgewertet. Ein Nil-Zugriff oder Funktionsaufruf im nicht gewählten Zweig passiert trotzdem. Hohe Konfidenz, wenn ein Zweig einen in der Bedingung geprüften Namen dereferenziert, mittlere bei einem Funktionsaufruf.

Mit Treffer:

```pascal
S := IfThen(Assigned(X), X.Name, '');
```

Richtig:

```pascal
if Assigned(X) then S := X.Name else S := '';
```

<a id="random-without-randomize"></a>
### random-without-randomize

**Random ohne Randomize** · Code Smell · Hinweis · Gruppe Robustheit und Muster

Random wird verwendet, aber die Unit ruft nie Randomize auf; jeder Start liefert dieselbe Folge. Randomize steht oft in der .dpr, deshalb ist die Regel standardmäßig aus und hat niedrige Konfidenz.

Mit Treffer:

```pascal
Dice := Random(6) + 1;
```

Richtig:

```pascal
Randomize; // once at program start
...
Dice := Random(6) + 1;
```

<a id="int32-mul-overflow"></a>
### int32-mul-overflow

**Int32-Multiplikation an Int64 zugewiesen** · Bug · Warnung · Gruppe Fehler finden

Beide Operanden haben höchstens 32 Bit; das Produkt wird in 32 Bit gerechnet und läuft über, bevor es der Int64-Variablen zugewiesen wird. Einen Operanden nach Int64 umwandeln.

Mit Treffer:

```pascal
Total := Width * Height; // Total: Int64; Width, Height: Integer
```

Richtig:

```pascal
Total := Int64(Width) * Height;
```

<a id="sizeof-pointer"></a>
### sizeof-pointer

**SizeOf eines Zeigers in Move oder FillChar** · Bug · Fehler · Gruppe Fehler finden

SizeOf eines Zeigers, Strings oder dynamischen Arrays ist die Größe des Verweises (4 oder 8 Byte), nicht die der Daten. Move und FillChar kopieren bzw. löschen dann zu wenig.

Mit Treffer:

```pascal
FillChar(Buffer[0], SizeOf(Buffer), 0); // Buffer: TBytes
```

Richtig:

```pascal
FillChar(Buffer[0], Length(Buffer) * SizeOf(Buffer[0]), 0);
```

<a id="char-to-pchar"></a>
### char-to-pchar

**Char nach PChar umgewandelt** · Bug · Fehler · Gruppe Fehler finden

PChar(C) mit einer Char-Variablen macht aus dem Zeichencode eine Adresse. Gemeint war ein String.

Mit Treffer:

```pascal
ShowMessage(PChar(C)); // C: Char
```

Richtig:

```pascal
ShowMessage(PChar(string(C)));
```

<a id="unrelated-class-cast"></a>
### unrelated-class-cast

**Harte Umwandlung zwischen nicht verwandten Klassen** · Bug · Warnung · Gruppe Fehler finden

TButton(Obj) prüft nichts. Ist der statische Typ von Obj weder Vorfahr noch Nachfahr von TButton (z. B. TEdit oder TForm), liest der Zugriff Speicher eines Objekts mit anderem Aufbau. Gemeldet wird nur, wenn beide Typen sicher bekannt sind, beide Vererbungsketten bis TObject bekannt sind und beide Deklarationen immer mit der Umwandlung übersetzt werden. Interfaces, Zeiger, Zahlen, TObject als Quelle und Umwandlungen in oder aus Klassenreferenzen (class of) bleiben still, ebenso der Zugriffsklassen-Trick: Das Ziel und seine Vorfahren bis zu einem gemeinsamen Vorfahren deklarieren weder Felder noch neue virtuelle Methoden (THackControl = class(TControl)), der Aufbau ist also derselbe. Sicherheit hoch. Korrektur: (Obj as TButton) prüft den Typ zur Laufzeit.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowTypes` | string-list | `[]` | Typen, die absichtlich hart umgewandelt werden: ein Typname (als Quelle oder Ziel) oder ein Paar "Quelle=Ziel". |

Mit Treffer:

```pascal
procedure TForm1.EditExit(Sender: TObject);
var
  mEdit: TEdit;
begin
  mEdit := Sender as TEdit;
  TButton(mEdit).Caption := 'OK';
end;
```

Richtig:

```pascal
procedure TForm1.EditExit(Sender: TObject);
var
  mEdit: TEdit;
begin
  mEdit := Sender as TEdit;
  (mEdit as TButton).Caption := 'OK';
end;
```

<a id="first-char-address"></a>
### first-char-address

**Adresse des ersten Zeichens über S[1]** · Bug · Warnung · Gruppe Fehler finden

@S[1] und PChar(@S[1]) lösen bei leerem String mit {$R+} einen Bereichsfehler aus, ohne Bereichsprüfung ergibt sich nil oder Müll. Außerdem erzwingt der Indexzugriff eine eindeutige Kopie (UniqueString). PChar(S) und Pointer(S) sind auch für leere Strings sicher. Gilt für string, UnicodeString, WideString, AnsiString, RawByteString und UTF8String, auch S[Low(S)]; ShortString, Arrays und andere Indizes bleiben still. Gemeldet wird nur, wenn der Typ von S sicher bekannt ist. Sicherheit hoch. Korrektur bei const-Parametern: durch PChar(S) ersetzen (PAnsiChar bei AnsiString-Typen), ein umgebendes PChar(…), PAnsiChar(…), PWideChar(…), PByte(…) oder Pointer(…) wird als Ganzes ersetzt. Bei anderen Strings kann der Zeiger zum Schreiben dienen, dann ist die eigene Kopie gewollt; dort gibt es keine Korrektur, die Meldung nennt UniqueString(S).

Mit Treffer:

```pascal
procedure Send(const AText: string);
begin
  WriteBuffer(@AText[1], Length(AText) * SizeOf(Char));
end;
```

Richtig:

```pascal
procedure Send(const AText: string);
begin
  WriteBuffer(PChar(AText), Length(AText) * SizeOf(Char));
end;
```

<a id="float-equality"></a>
### float-equality

**Gleitkommavergleich mit = oder <>** · Bug · Hinweis · Gruppe Fehler finden

Gleitkommawerte sind nach Berechnungen selten exakt gleich. Mit SameValue aus System.Math und einer Toleranz vergleichen. Vergleiche mit 0 werden nicht gemeldet.

Mit Treffer:

```pascal
if Total = Expected then
```

Richtig:

```pascal
if SameValue(Total, Expected) then
```

<a id="constructor-on-instance"></a>
### constructor-on-instance

**Konstruktor auf einer Instanz aufgerufen** · Bug · Warnung · Gruppe Fehler finden

Create wird auf einer Variablen statt auf der Klasse aufgerufen. Das legt kein neues Objekt an; mit nicht zugewiesener Variable stürzt es ab. Klassenreferenzen (class of …) werden nicht gemeldet.

Mit Treffer:

```pascal
List.Create; // List: TStringList
```

Richtig:

```pascal
List := TStringList.Create;
```

<a id="format-without-settings"></a>
### format-without-settings

**Formatierung abhängig vom Gebietsschema** · Code Smell · Hinweis · Gruppe Robustheit und Muster

Format mit %f, %n, %m, %g oder %e und Funktionen wie FloatToStr, StrToFloat oder DateToStr ohne TFormatSettings-Parameter verwenden das Gebietsschema des Benutzers (Dezimaltrenner, Datumsformat). Für Dateien, Protokolle und Logs feste TFormatSettings übergeben. Format('%d', …) wird nicht gemeldet, ebenso wenig FormatDateTime und FormatFloat mit festem Bild ohne Trennzeichen (: / . ,) wie 'yyyy"-"mm"-"dd' oder 'ddddd t'.

Mit Treffer:

```pascal
Line := Format('%.2f', [Amount]);
```

Richtig:

```pascal
Line := Format('%.2f', [Amount], TFormatSettings.Invariant);
```

<a id="format-args"></a>
### format-args

**Formatstring passt nicht zu den Argumenten** · Bug · Fehler · Gruppe Fehler finden

Format, FmtStr, FormatBuf, StrFmt, StrLFmt, WideFormat, WideFmtStr, Exception.CreateFmt bzw. CreateFmtHelp und TStringBuilder.AppendFormat mit bekanntem Formatstring (Literal, mit + verbundene Literale, const oder resourcestring der Datei bzw. des Index), dessen Platzhalter nicht zur Argumentliste [...] passen: ungültiger Platzhalter (%q, '%' bzw. '%5' am Ende, %0: ohne Typbuchstaben), weniger Argumente als Platzhalter oder ein Argument vom falschen Typ: %d %u %x nur Ganzzahlen, %e %f %g %n %m nur Gleitkommazahlen, %s Strings, Zeichen und Variants, %p Zeiger und Objekte, ein * für Breite bzw. Genauigkeit eine Ganzzahl; Variants passen überall. Boolean und Aufzählungswerte werden bei jedem Typbuchstaben gemeldet, mit Ord(...) bzw. BoolToStr(..., True) als Hinweis. All das löst zur Laufzeit EConvertError aus. Ein Argument hinter dem letzten verwendeten wird mit mittlerer Sicherheit gemeldet (nur ohne Index im Formatstring), es wird nie ausgegeben. Typen werden nur geprüft, wenn sie sicher bekannt sind; Formatstrings aus Variablen, Index * und Bereiche bleiben still. Eigene Routinen namens Format bleiben still, wenn die Namensauflösung sie findet. Teilt die Zerlegung der Formatstrings mit format-without-settings. Keine Korrektur. Sicherheit hoch.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `formatMethods` | string-list | `[]` | Weitere Routinen mit Formatstring und folgender Argumentliste array of const, z. B. "TLogger.LogFmt" oder "Protokoll". Mit Punkt zählt ohne Namensauflösung der Methodenname hinter einem beliebigen Qualifizierer. |

Mit Treffer:

```pascal
Result := Format('%d orders for %s', [ACustomer.Name]);
```

Richtig:

```pascal
Result := Format('%d orders for %s', [ACustomer.OrderCount, ACustomer.Name]);
```

<a id="generic-exception-raised"></a>
### generic-exception-raised

**Allgemeine Exception ausgelöst** · Code Smell · Hinweis · Gruppe Exceptions

Wer die Basisklasse Exception auslöst, nimmt Aufrufern die Möglichkeit, den Fehler gezielt zu behandeln. Besser eine eigene Exception-Klasse deklarieren.

Mit Treffer:

```pascal
raise Exception.Create('Customer missing');
```

Richtig:

```pascal
raise ECustomerMissing.Create('Customer missing');
```

<a id="catch-all-without-raise"></a>
### catch-all-without-raise

**Exception-Handler ohne erneutes raise** · Code Smell · Warnung · Gruppe Exceptions

Ein Handler für Exception, der weder erneut auslöst noch das Programm beendet, verschluckt jeden Fehler, auch Programmierfehler. Standardmäßig aus; gedacht für Bibliothekscode.

Mit Treffer:

```pascal
except
  on E: Exception do
    Log(E.Message);
end;
```

Richtig:

```pascal
except
  on E: Exception do
  begin
    Log(E.Message);
    raise;
  end;
end;
```

<a id="exception-freed"></a>
### exception-freed

**Exception-Objekt manuell freigegeben** · Bug · Fehler · Gruppe Exceptions

Die RTL gibt ein Exception-Objekt nach seinem Handler bzw. nach raise selbst frei. Manuelles Freigeben führt zur doppelten Freigabe.

Mit Treffer:

```pascal
on E: Exception do
  E.Free;
```

Richtig:

```pascal
on E: Exception do
  Log(E.Message);
```

<a id="string-concat-in-loop"></a>
### string-concat-in-loop

**String-Verkettung in einer Schleife** · Code Smell · Hinweis · Gruppe Performance

Eine String-Variable wird in einer Schleife schrittweise verlängert. Delphi vergrößert Strings meist an Ort und Stelle, deshalb nur mit niedriger Konfidenz und standardmäßig aus; bei vielen Durchläufen ist TStringBuilder schneller.

Mit Treffer:

```pascal
for I := 1 to 10000 do
  S := S + IntToStr(I);
```

Richtig:

```pascal
Builder := TStringBuilder.Create;
try
  for I := 1 to 10000 do
    Builder.Append(I);
  S := Builder.ToString;
finally
  Builder.Free;
end;
```

<a id="loop-invariant-call"></a>
### loop-invariant-call

**Teurer Aufruf in der Schleifenbedingung** · Code Smell · Hinweis · Gruppe Performance

Die Bedingung von while und until wird bei jedem Durchlauf ausgewertet. Aufrufe wie Trim, Format oder FileExists und Eigenschaften wie Lines.Text werden dort jedes Mal neu berechnet; besser einmal vor der Schleife. Die Grenzen von for werden nur einmal ausgewertet und nicht gemeldet. Standardmäßig aus.

Mit Treffer:

```pascal
while I < Length(Trim(Memo.Lines.Text)) do
  Inc(I);
```

Richtig:

```pascal
Text := Trim(Memo.Lines.Text);
while I < Length(Text) do
  Inc(I);
```

<a id="missing-begin-update"></a>
### missing-begin-update

**Hinzufügen in einer Schleife ohne BeginUpdate** · Code Smell · Hinweis · Gruppe Performance

Items.Add, Lines.Add und ähnliche Aufrufe in einer Schleife zeichnen das Steuerelement bei jedem Aufruf neu. Die Schleife mit BeginUpdate und try … finally EndUpdate umschließen. Standardmäßig aus.

Mit Treffer:

```pascal
for I := 1 to 1000 do
  ListBox1.Items.Add(IntToStr(I));
```

Richtig:

```pascal
ListBox1.Items.BeginUpdate;
try
  for I := 1 to 1000 do
    ListBox1.Items.Add(IntToStr(I));
finally
  ListBox1.Items.EndUpdate;
end;
```

<a id="setlength-in-loop"></a>
### setlength-in-loop

**Array wächst in der Schleife um je ein Element** · Code Smell · Hinweis · Gruppe Performance

SetLength(A, Length(A) + 1) in einer Schleife kopiert das dynamische Array bei jedem Durchlauf. Die Regel meldet nur, wenn A sicher ein dynamisches Array ist (array of, TArray<T>, ein Array-Typ der Datei oder ein bekannter RTL-Typ wie TBytes), nie bei Strings. In einer for-Schleife ist die Anzahl bekannt: Die Meldung nennt sie, und ist A eine lokale Variable, die vor der Schleife nicht benutzt und darin nur als A[High(A)] bzw. A[Length(A) - 1] beschrieben wird, setzt die Schnellkorrektur die Länge einmal vor der Schleife und indiziert mit der Schleifenvariable. Sonst die Werte in einer TList<T> sammeln.

Mit Treffer:

```pascal
for I := 0 to Liste.Count - 1 do
begin
  SetLength(Namen, Length(Namen) + 1);
  Namen[High(Namen)] := Liste[I].Name;
end;
```

Richtig:

```pascal
SetLength(Namen, Liste.Count);
for I := 0 to Liste.Count - 1 do
  Namen[I] := Liste[I].Name;
```

<a id="managed-param-without-const"></a>
### managed-param-without-const

**Verwalteter Parameter ohne const** · Code Smell · Hinweis · Gruppe Performance

Ein Wertparameter vom Typ String, Interface, dynamisches oder offenes Array oder ein Record der Datei ab minRecordSize Byte, den die Routine nie verändert. Jeder Aufruf zahlt Referenzzählung bzw. Kopie; const spart beides. Verändert heißt: zugewiesen, ein Teil zugewiesen (Zeichen, Felder, Elemente), an var oder out übergeben, @Parameter, Methodenaufruf an einem Record, Laufvariable einer for-Schleife. Die Regel meldet nur, wenn das sicher ist: Aufrufe mit unbekannter Signatur (Methoden ohne Symbolindex, Überladungen), with-Blöcke, Einfangen in anonymen Methoden, inherited ohne Namen und asm lassen sie schweigen. Virtuelle, dynamische, abstrakte und message-Methoden, Aufrufkonventionen, external- und exportierte Routinen, Methoden von Klassen mit Interfaces, published-Methoden und als Wert benutzte Methoden (Ereignisse, @Routine, Formulardatei) bleiben außen vor, weil ihre Signatur von außen vorgegeben ist; Overrides nur mit ignoreOverrides = false und dann ohne Korrektur. Die Korrektur ergänzt const in Rumpf und Deklaration und teilt Parametergruppen bei Bedarf. Verweise als Methodenzeiger in anderen Units sieht die Regel nicht; die meldet nach der Korrektur der Compiler.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `minRecordSize` | integer | `16` | Record-Parameter ab dieser Größe in Byte melden. |
| `ignoreOverrides` | boolean | `true` | Overrides nicht melden; ihre Signatur gibt der Vorfahr vor. |

Mit Treffer:

```pascal
function Formatieren(Text: string; Kunde: TKundenDaten): string;
begin
  Result := Text + Kunde.Name;
end;
```

Richtig:

```pascal
function Formatieren(const Text: string; const Kunde: TKundenDaten): string;
begin
  Result := Text + Kunde.Name;
end;
```

<a id="bool-compare"></a>
### bool-compare

**Vergleich mit True oder False** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Vergleich eines Boolean mit True oder False ist überflüssig; den Ausdruck oder not direkt verwenden.

Mit Treffer:

```pascal
if Visible = True then
  Show;
```

Richtig:

```pascal
if Visible then
  Show;
```

<a id="redundant-assigned-free"></a>
### redundant-assigned-free

**Assigned-Prüfung vor Free** · Code Smell · Hinweis · Gruppe Stil und Metriken

Free prüft selbst auf nil, eine Assigned-Prüfung vor Free oder FreeAndNil ist überflüssig.

Mit Treffer:

```pascal
if Assigned(List) then
  List.Free;
```

Richtig:

```pascal
List.Free;
```

<a id="raise-in-finally"></a>
### raise-in-finally

**raise in einem finally-Block** · Bug · Warnung · Gruppe Exceptions

Eine im finally-Block ausgelöste Exception ersetzt die gerade laufende Exception, die dadurch verloren geht.

Mit Treffer:

```pascal
try
  Work;
finally
  raise Exception.Create('Fehler');
end;
```

Richtig:

```pascal
try
  Work;
finally
  Cleanup;
end;
```

<a id="redundant-parens"></a>
### redundant-parens

**Überflüssige Klammern** · Code Smell · Hinweis · Gruppe Stil und Metriken

Klammern um eine ganze Bedingung oder einen einzelnen Bezeichner bringen nichts. Standardmäßig aus.

Mit Treffer:

```pascal
if (Done) then
  Exit;
```

Richtig:

```pascal
if Done then
  Exit;
```

<a id="redundant-cast"></a>
### redundant-cast

**Überflüssige Typumwandlung** · Code Smell · Hinweis · Gruppe Stil und Metriken

TStringList(Liste) mit Liste: TStringList, X as TFoo mit X: TFoo oder Integer(Anzahl) mit Anzahl: Integer ändern nichts. Ebenso TObject(Obj).Free: Free ruft den virtuellen Destruktor und braucht keine Umwandlung (Option checkFree). Gemeldet wird nur, wenn der Typ der Quelle sicher bekannt und genau mit dem Namen des Ziels deklariert ist; Aliase (TFarbIndex = Integer), Konstanten, Routinen ohne Aufruf, überladene Routinen als Quelle, Argumente überladener Aufrufe (die Umwandlung kann die Überladung wählen), as mit Interfaces (QueryInterface) und in der Klassenkette neu deklariertes Free bleiben still. Sicherheit hoch. Korrektur: die Umwandlung entfernen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `checkFree` | boolean | `true` | Auch eine Klassenumwandlung melden, die nur vor Free steht (CastAndFree). |

Mit Treffer:

```pascal
procedure TImport.Cleanup;
begin
  TStringList(FLines).Clear;
  TObject(FStream).Free;
end;
```

Richtig:

```pascal
procedure TImport.Cleanup;
begin
  FLines.Clear;
  FStream.Free;
end;
```

<a id="redundant-begin-end"></a>
### redundant-begin-end

**begin … end um eine einzelne Anweisung** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein begin … end-Block mit genau einer Anweisung kann entfallen. Standardmäßig aus.

Schweigt, solange [`missing-begin-end`](#missing-begin-end) an ist.

Mit Treffer:

```pascal
if Done then
begin
  Exit;
end;
```

Richtig:

```pascal
if Done then
  Exit;
```

<a id="with-statement"></a>
### with-statement

**with-Anweisung** · Code Smell · Hinweis · Gruppe Stil und Metriken

In einem with-Block ist unklar, zu welchem Objekt ein Bezeichner gehört, und ein neues Mitglied des with-Objekts ändert still die Bedeutung. Den Ausdruck ausschreiben oder eine lokale Variable verwenden.

Mit Treffer:

```pascal
with Customer do
  Name := Edit.Text;
```

Richtig:

```pascal
Customer.Name := Edit.Text;
```

<a id="metric-method-length"></a>
### metric-method-length

**Methode zu lang** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteilen. Den Grenzwert setzt die Option max, z. B. "rules": {"metric-method-length": {"max": 80}}.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `60` | Höchstens so viele Anweisungszeilen. |

Mit Treffer:

```pascal
procedure TImport.Run;
begin
  // 120 lines: read, check, convert and save
end;
```

Richtig:

```pascal
procedure TImport.Run;
begin
  Read;
  Check;
  Convert;
  Save;
end;
```

<a id="metric-nesting-depth"></a>
### metric-nesting-depth

**Zu tief verschachtelt** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder innere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `4` | Höchste erlaubte Schachtelungstiefe. |

Mit Treffer:

```pascal
for Item in Items do
  if Item.Active then
    for Line in Item.Lines do
      if Line.Valid then
        try
          Save(Line);
        except
          Log;
        end;
```

Richtig:

```pascal
for Item in Items do
  if Item.Active then
    SaveLines(Item);
```

<a id="metric-cyclomatic-complexity"></a>
### metric-cyclomatic-complexity

**Zyklomatische Komplexität zu hoch** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/or in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `15` | Höchste erlaubte zyklomatische Komplexität. |

Mit Treffer:

```pascal
case Kind of
  1: A;
  2: B;
  // ... 20 branches
end;
```

Richtig:

```pascal
Handlers[Kind]();
```

<a id="metric-cognitive-complexity"></a>
### metric-cognitive-complexity

**Kognitive Komplexität zu hoch** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else, else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `15` | Höchste erlaubte kognitive Komplexität. |

Mit Treffer:

```pascal
if A then
  for I := 0 to N do
    if B and C or D then
      while E do
        F;
```

Richtig:

```pascal
if not A then
  Exit;
for I := 0 to N do
  ProcessItem(I);
```

<a id="metric-parameter-count"></a>
### metric-parameter-count

**Zu viele Parameter** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `6` | Höchstens so viele Parameter. |

Mit Treffer:

```pascal
procedure Book(const AName, AStreet, ACity, AZip: string; AAmount: Currency; ADate: TDate; ANote: string);
```

Richtig:

```pascal
procedure Book(const AAddress: TAddress; const AOrder: TOrder);
```

<a id="metric-boolean-operands"></a>
### metric-boolean-operands

**Bedingung mit zu vielen Operanden** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Bedingung von if, while, until oder einem Bedingungsausdruck verknüpft mehr Operanden mit and, or und xor als der Grenzwert (Vorgabe 5); Klammern und not zählen nicht, ein Vergleich oder Aufruf ist ein Operand. Der Befund steht auf der Bedingung. Schnellkorrektur „Bedingung in Funktion auslagern“ (#50) macht aus der ganzen Bedingung eine Funktion mit Ergebnis Boolean (Methode der Klasse bzw. Routine vor der umgebenden), die gelesenen lokalen Namen werden const-Parameter. Erscheint auch in der Metrik-Linse.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `5` | Höchstens so viele Operanden in einer Bedingung. |

Mit Treffer:

```pascal
if (Kunde.Aktiv) and (Kunde.Land = 'DE') and (Betrag > 0) and
   (not Gesperrt) and (Datum >= Start) and (Datum <= Ende) then
```

Richtig:

```pascal
if IstBuchbar(Kunde, Betrag, Gesperrt, Datum, Start, Ende) then
```

<a id="metric-local-count"></a>
### metric-local-count

**Zu viele lokale Variablen** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Routine deklariert mehr lokale Variablen als der Grenzwert (Vorgabe 12): Namen im var-Abschnitt, Inline-Variablen und for var. Lokale Routinen und anonyme Methoden zählen für sich. Viele lokale Variablen heißen meist, dass die Routine mehreres tut; Teile in eigene Methoden auslagern. Erscheint auch in der Metrik-Linse.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `12` | Höchstens so viele lokale Variablen. |

Mit Treffer:

```pascal
procedure Abschluss;
var
  Summe, Netto, Steuer, Rabatt, Skonto, Porto: Currency;
  Kunde, Konto, Beleg, Datei, Zeile, Text, Pfad: string;
```

Richtig:

```pascal
procedure Abschluss;
var
  Beleg: TBeleg;
begin
  Beleg := BerechneBeleg;
  SchreibeBeleg(Beleg);
```

<a id="metric-exit-points"></a>
### metric-exit-points

**Zu viele Ausstiege** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Routine wird öfter mit Exit und raise verlassen als der Grenzwert (Vorgabe 4); Exit(Wert) und raise; im except zählen mit. Lokale Routinen und anonyme Methoden zählen für sich. Viele Ausstiege machen den Ablauf schwer lesbar; Wächter zusammenfassen oder Teile auslagern. Erscheint auch in der Metrik-Linse.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `4` | Höchstens so viele Exit und raise. |

Mit Treffer:

```pascal
if A = nil then Exit;
if B = nil then Exit;
if not Valid then raise EError.Create('...');
if Done then Exit(True);
if Cancel then Exit(False);
```

Richtig:

```pascal
if not Ready(A, B) then
  Exit;
Result := Process(A, B);
```

<a id="todo-comment"></a>
### todo-comment

**Offener TODO-Kommentar** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Priorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. "rules": {"todo-comment": {"severity": "hint"}}. Erledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe ["TODO", "FIXME"]); sie gilt auch für get_todos und --todos.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `keywords` | string-list | `["TODO","FIXME"]` | Marken offener TODO-Einträge (nur Buchstaben). |

Mit Treffer:

```pascal
// TODO 1 -oMarco -cGUI : set focus
Edit.Text := '';
```

Richtig:

```pascal
Edit.Text := '';
Edit.SetFocus;
```

<a id="component-palette-icon"></a>
### component-palette-icon

**Registrierte Komponente ohne Palettensymbol** · Code Smell · Hinweis · Gruppe Komponenten

Jede an RegisterComponents übergebene Klasse braucht in einer per {$R} eingebundenen .dcr oder .res eine Bitmap mit dem Klassennamen in Großbuchstaben. Ab Delphi 11 werden zusätzlich die Größen 16, 24 und 32 px (NAME16, NAME24, NAME32) erwartet. Ohne lesbare eingebundene Ressourcendatei schweigt die Regel.

Mit Treffer:

```pascal
{$R *.dcr} // without TMYBUTTON
RegisterComponents('Samples', [TMyButton]);
```

Richtig:

```pascal
{$R *.dcr} // with TMYBUTTON16, TMYBUTTON24, TMYBUTTON32
RegisterComponents('Samples', [TMyButton]);
```

<a id="unresolved-identifier"></a>
### unresolved-identifier

**Nicht deklarierter Bezeichner** · Bug · Warnung · Gruppe Fehler finden

Ein Bezeichner in einer Anweisung ist weder in der Unit noch in den eingebundenen Units deklariert (wie Compilerfehler E2003). Geprüft beim Tippen, ohne Compiler; with-Blöcke, asm und anonyme Methoden werden übersprungen.

Mit Treffer:

```pascal
procedure Foo;
begin
  Lst.Add('x');
end;
```

Richtig:

```pascal
procedure Foo;
var
  Lst: TStringList;
begin
  Lst := TStringList.Create;
  Lst.Add('x');
end;
```

<a id="deprecated-symbol"></a>
### deprecated-symbol

**Veraltetes oder gebundenes Symbol** · Code Smell · Warnung · Gruppe Compiler vorab

Eine Routine, ein Typ, eine Konstante oder ein Mitglied mit deprecated, experimental, platform oder library wird verwendet (wie W1000, W1003, W1002, W1001), oder eine Unit, deren Kopf einen dieser Hinweise trägt, steht in uses (wie W1006, W1007, W1005, W1004). Gemeldet wird nur, was sicher aufgelöst ist. Der Editor streicht veraltete Namen durch; die Meldung nennt den Grund aus deprecated 'Grund'. Die Deklaration und der Kopf ihrer Implementierung werden nicht gemeldet. Welche Arten gemeldet werden, legt die Option kinds fest (Standard deprecated und experimental, wie meist in Projekten); die Schalter {$WARN SYMBOL_DEPRECATED OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_PLATFORM …} usw. und {$WARNINGS OFF} gelten ab ihrer Stelle wie beim Compiler; ein Schalter in einem {$IF}-Zweig, der nicht sicher mit übersetzt wird, hält die Stelle still. Korrektur: durch den Namen aus dem Grund ersetzen (bei IncludeTrailingBackslash und ExcludeTrailingBackslash durch die plattformunabhängige Routine), wenn genau ein Name passt, an der Stelle sichtbar ist und dieselbe Art hat. Ohne Projektindex prüft die Regel nur die Symbole der Datei selbst.

Entspricht der Compilermeldung `W1000`, `W1001`, `W1002`, `W1003`, `W1004`, `W1005`, `W1006`, `W1007`.

Stufe B (Namensauflösung über Units).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `kinds` | string-list | `["deprecated","experimental"]` | Gemeldete Arten: deprecated, experimental, platform, library (platform und library sind standardmäßig aus). |

Mit Treffer:

```pascal
Pfad := IncludeTrailingBackslash(Basis) + Name;
```

Richtig:

```pascal
Pfad := IncludeTrailingPathDelimiter(Basis) + Name;
```

<a id="implicit-package-import"></a>
### implicit-package-import

**Implizit eingebundene Unit** · Code Smell · Warnung · Gruppe Packages und Tests

In einem Package (.dpk) verwendet eine Unit aus contains eine Unit, die weder in contains steht noch von einem Package aus requires geliefert wird. Der Compiler zieht sie implizit hinein (W1033), was später zu doppelten Units führt, wenn ein anderes Package sie ebenfalls enthält. Die Schnellkorrektur nimmt die Unit in contains auf.

Mit Treffer:

```pascal
package Werkzeuge;
requires rtl;
contains
  uHaupt in 'uHaupt.pas';  // uHaupt uses uMathe
end.
```

Richtig:

```pascal
package Werkzeuge;
requires rtl;
contains
  uHaupt in 'uHaupt.pas',
  uMathe in 'uMathe.pas';
end.
```

<a id="type-used-before-declaration"></a>
### type-used-before-declaration

**Typ vor seiner Deklaration benutzt** · Bug · Fehler · Gruppe Fehler finden

Eine Klasse, ein Interface, ein Record oder ein anderer Typ wird in einer Typdeklaration (Feld, Parameter, Ergebnis, Property, generisches Argument, class of) benutzt, ist aber erst weiter unten im selben Gültigkeitsbereich deklariert (wie Compilerfehler E2003). Vorfahren, Aliase und Zeigertypen werden nicht gemeldet. Schnellkorrekturen: Forward-Deklaration am Anfang des type-Blocks ergänzen, type-Blöcke zusammenlegen (const-, var- und label-Abschnitte dazwischen wandern vor den ersten Block) oder einen Record vor seinen ersten Verwender verschieben; ohne sichere Korrektur nennt die Meldung den Grund.

Mit Treffer:

```pascal
type
  TTree = class
    FRoot: TNode;
  end;
  TNode = class
  end;
```

Richtig:

```pascal
type
  TNode = class;
  TTree = class
    FRoot: TNode;
  end;
  TNode = class
  end;
```

<a id="unneeded-forward-declaration"></a>
### unneeded-forward-declaration

**Überflüssige Forward-Deklaration** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Forward-Deklaration, deren Typ im selben type-Block vor der vollständigen Deklaration nicht benutzt wird. Schnellkorrektur: entfernen.

Mit Treffer:

```pascal
type
  TNode = class;
  TNode = class
  end;
```

Richtig:

```pascal
type
  TNode = class
  end;
```

<a id="field-not-freed"></a>
### field-not-freed

**Feld erzeugt, aber nie freigegeben** · Bug · Warnung · Gruppe Fehler finden

Ein Objektfeld, das der Konstruktor (oder eine von ihm aufgerufene private Methode) mit TKlasse.Create erzeugt, wird in der Klasse nirgends freigegeben (kein Free, FreeAndNil, Destroy oder DisposeOf): ein Speicherleck. Ausgenommen sind Komponenten mit einem Owner ungleich nil, Interface- und Record-Felder sowie die Klassen aus der Option ignoreTypes; TObjectList- und TObjectDictionary-Felder sind normale Felder. Konfidenz mittel. Schnellkorrekturen: das Feld im Destruktor freigeben oder alle eigenen Objekte der Klasse freigeben; ein fehlender Destruktor wird mit override und inherited angelegt. Die Freigaben stehen vor inherited in umgekehrter Erzeugungsreihenfolge, als Free oder FreeAndNil (refactoring.freeFieldsStyle). Bis #918 hieß die Regel owned-field-not-freed; Einstellungen und Unterdrückungen mit dieser Kennung wirken weiter.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignoreTypes` | string-list | `[]` | Klassen, die anderswo freigegeben werden; generische Typen treffen ohne Typparameter. |

Mit Treffer:

```pascal
constructor TImport.Create;
begin
  FZeilen := TStringList.Create;
  FFehler := TStringList.Create;
end;

destructor TImport.Destroy;
begin
  FZeilen.Free;
  inherited;
end;
```

Richtig:

```pascal
destructor TImport.Destroy;
begin
  FFehler.Free;
  FZeilen.Free;
  inherited;
end;
```

<a id="owned-field-free-unclear"></a>
### owned-field-free-unclear

**Unklar, ob ein erzeugtes Feld freigegeben werden muss** · Bug · Hinweis · Gruppe Fehler finden

Ein im Konstruktor erzeugtes, nicht freigegebenes Objektfeld wird auch zurückgegeben (Result := FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an dessen Add…, Insert…, Register…, Attach…, Push oder Enqueue übergeben, ohne Create zugewiesen oder ist über eine Property (write FFeld) schreibbar. Ob die Klasse das Objekt noch besitzt, entscheidet der Entwickler; deshalb gibt es keine Schnellkorrektur.

Mit Treffer:

```pascal
function TCache.Take: TList;
begin
  Result := FList;  // created in Create, never freed
end;
```

Richtig:

```pascal
function TCache.Take: TList;
begin
  Result := FList;
  FList := nil;  // ownership passes to the caller
end;
```

<a id="operator-precedence"></a>
### operator-precedence

**Vorrang von not übersehen** · Bug · Warnung · Gruppe Fehler finden

In Pascal bindet not stärker als in und Vergleiche: not X in Menge heißt (not X) in Menge, not A = B heißt (not A) = B, bei Ganzzahlen wird not bitweise. Die Regel meldet diese Formen, wenn der deklarierte Typ des Operanden zeigt, dass es nicht gemeint sein kann (kein Boolean). Schnellkorrektur: Klammern setzen, not (X in Menge).

Mit Treffer:

```pascal
if not Zustand in [zsOffen, zsGesperrt] then
  Bearbeiten;
```

Richtig:

```pascal
if not (Zustand in [zsOffen, zsGesperrt]) then
  Bearbeiten;
```

<a id="empty-statement"></a>
### empty-statement

**Leere Anweisung nach then, do oder else** · Bug · Warnung · Gruppe Fehler finden

Ein Semikolon direkt nach then, do oder else beendet die Anweisung: Die folgende Zeile läuft dann immer bzw. die Schleife dreht leer. Ein leerer Block begin … end nach then, do oder else wird ebenfalls gemeldet, außer er enthält einen erklärenden Kommentar (Option allowCommented). Ein Semikolon direkt vor end, until, except oder finally ändert nichts und bleibt unbeanstandet. Schnellkorrektur: Semikolon entfernen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowCommented` | boolean | `true` | begin { absichtlich leer } end nicht melden. |

Mit Treffer:

```pascal
if Liste.Count = 0 then;
  raise EKeineDaten.Create('Keine Daten');
```

Richtig:

```pascal
if Liste.Count = 0 then
  raise EKeineDaten.Create('Keine Daten');
```

<a id="loop-off-by-one"></a>
### loop-off-by-one

**Schleife läuft einen Schritt zu weit** · Bug · Warnung · Gruppe Fehler finden

for I := 0 to Liste.Count oder to Length(A) über nullbasierte Listen und Arrays greift im letzten Durchlauf hinter das Ende, wenn der Rumpf Liste[I] bzw. A[I] liest. Bei einsbasierten Strings umgekehrt: S[0] und for I := 0 to Length(S) greifen vor das erste Zeichen; {$ZEROBASEDSTRINGS ON} wird beachtet. Schnellkorrektur: - 1 ergänzen bzw. High(A) verwenden, bei Strings Low(S) und High(S). Die Option countNames nennt die Namen, die eine Anzahl liefern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `countNames` | string-list | `["Count","Length"]` | Namen, die eine Anzahl liefern (Property wie Count oder Funktion wie Length). |

Mit Treffer:

```pascal
for I := 0 to Kunden.Count do
  Ausgabe(Kunden[I].Name);
```

Richtig:

```pascal
for I := 0 to Kunden.Count - 1 do
  Ausgabe(Kunden[I].Name);
```

<a id="collection-modified-in-loop"></a>
### collection-modified-in-loop

**Liste in der eigenen Schleife verändert** · Bug · Warnung · Gruppe Fehler finden

Delete, Remove, Add oder eine andere Methode aus der Option mutatingMethods wird auf der Liste aufgerufen, über die die Schleife gerade vorwärts per Index oder mit for … in läuft. Vorwärts überspringt Delete das nächste Element und läuft über das Ende, Add wird nicht mehr durchlaufen und Insert liefert dasselbe Element zweimal; mit for … in wirft die RTL eine Exception. Ein Break oder Exit direkt nach dem Aufruf beendet die Schleife und bleibt still, downto-Schleifen ebenso. Schnellkorrektur bei Indexschleifen: rückwärts mit downto; bei for … in die Elemente sammeln und die Liste nach der Schleife ändern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `mutatingMethods` | string-list | `["Add","Insert","Delete","Remove","Extract","Clear"]` | Methoden, die die Liste verändern. |

Mit Treffer:

```pascal
for I := 0 to Liste.Count - 1 do
  if Liste[I].Erledigt then
    Liste.Delete(I);
```

Richtig:

```pascal
for I := Liste.Count - 1 downto 0 do
  if Liste[I].Erledigt then
    Liste.Delete(I);
```

<a id="use-after-free"></a>
### use-after-free

**Objekt nach Free weiter benutzt** · Bug · Fehler · Gruppe Fehler finden

Nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) oder Dispose(X) wird X ohne neue Zuweisung wieder benutzt: Methode, Feld, Index oder X^, with X, nach Free auch Assigned(X) (immer True) oder ein zweites Free. Die Regel folgt dem Datenfluss der Routine; eine Zuweisung an X, die Übergabe von X an eine Routine, @X und nach FreeAndNil eine Abfrage auf nil beenden den Weg, Wege nur über eine mögliche Ausnahme bleiben aus. Konfidenz hoch, wenn Freigabe und Zugriff im selben Block nacheinander stehen, sonst mittel. Keine automatische Korrektur; die Aktion springt zur Freigabe.

Mit Treffer:

```pascal
Bericht.Free;
Protokoll.Add('Seiten: ' + IntToStr(Bericht.Seiten));
```

Richtig:

```pascal
Protokoll.Add('Seiten: ' + IntToStr(Bericht.Seiten));
Bericht.Free;
```

<a id="deref-before-nil-check"></a>
### deref-before-nil-check

**Erst benutzt, dann auf nil geprüft** · Bug · Warnung · Gruppe Fehler finden

X wird dereferenziert (X.Feld, X.Methode, X^) und erst danach mit Assigned(X), X <> nil oder X = nil geprüft. Entweder ist die Prüfung überflüssig oder der Zugriff davor kann knallen. Gemeldet wird nur, wenn jeder Weg zur Prüfung durch den Zugriff führt und X vorher nicht geprüft wurde; eine neue Zuweisung, die Übergabe von X an eine Routine und bei Feldern und globalen Variablen jeder Aufruf dazwischen beenden den Weg. Konfidenz mittel. Ist die Prüfung ein if ohne else direkt nach dem Zugriff im selben Block, zieht die Schnellkorrektur den Zugriff hinein.

Mit Treffer:

```pascal
Titel := Kunde.Name;
if Assigned(Kunde) then
  Anzeigen(Kunde);
```

Richtig:

```pascal
if Assigned(Kunde) then
begin
  Titel := Kunde.Name;
  Anzeigen(Kunde);
end;
```

<a id="field-free-without-nil"></a>
### field-free-without-nil

**Feld freigegeben, Verweis bleibt stehen** · Bug · Warnung · Gruppe Fehler finden

FFeld.Free in einer Methode außerhalb des Destruktors, und ein Weg zum Ende der Methode setzt das Feld nicht neu. Ein späterer Zugriff oder ein zweites Free trifft freigegebenen Speicher. Neu setzt eine Zuweisung oder der Aufruf einer Methode derselben Klasse, die das Feld zuweist. Felder sind die der Klassendeklaration in der Unit. Ausgenommen sind Destruktoren, Methoden mit [TearDown] oder [TearDownFixture], Methoden, die nur aus diesen aufgerufen werden, und die Methoden aus der Option ignoreMethods. Konfidenz mittel. Schnellkorrektur: FreeAndNil(FFeld).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignoreMethods` | string-list | `["Destroy","BeforeDestruction"]` | Methoden, in denen Free ohne nil erlaubt ist. |

Mit Treffer:

```pascal
procedure TImport.Zuruecksetzen;
begin
  FCache.Free;
end;
```

Richtig:

```pascal
procedure TImport.Zuruecksetzen;
begin
  FreeAndNil(FCache);
end;
```

<a id="missing-inherited"></a>
### missing-inherited

**Konstruktor oder Destruktor ohne inherited** · Bug · Warnung · Gruppe Fehler finden

Ein Konstruktor oder ein override von Destroy, AfterConstruction oder BeforeDestruction ruft inherited nicht auf, in jeder Klasse, deren Vorfahr nicht TObject ist. Konstruktoren werden nur gemeldet, wenn ein Vorfahr einen eigenen Konstruktor deklariert (Datei, Index oder bekannte RTL-/VCL-Klasse) und der Konstruktor keinen anderen Konstruktor derselben Klasse aufruft. Bei Komponenten meldet Destroy nur component-missing-inherited. Konfidenz hoch. Schnellkorrektur: inherited; am Ende von Destroy und BeforeDestruction, am Anfang von Konstruktoren und AfterConstruction; ein Konstruktor mit Parametern ohne override bekommt inherited Create;.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `methods` | string-list | `["Create","Destroy","AfterConstruction","BeforeDestruction"]` | Geprüfte Methoden; Create steht für alle Konstruktoren, deren Name mit Create beginnt. |

Mit Treffer:

```pascal
destructor TExport.Destroy;
begin
  FDatei.Free;
end;
```

Richtig:

```pascal
destructor TExport.Destroy;
begin
  FDatei.Free;
  inherited;
end;
```

<a id="inherited-order"></a>
### inherited-order

**inherited an der falschen Stelle** · Bug · Warnung · Gruppe Fehler finden

Im Destruktor steht inherited (inherited; bzw. inherited Destroy) als Anweisung des Rumpfs vor einer späteren Anweisung, die ein Feld der Klasse selbst freigibt (F.Free, F.DisposeOf, FreeAndNil(F), auch mit Self.): Der Vorfahr kann noch virtuelle Methoden aufrufen, die das Feld brauchen. Klassen, in deren Kette eine Klasse mit Thread im Namen steht, bleiben still, denn TThread.Destroy wartet auf Execute und gehört dort an den Anfang. Im Konstruktor greifen die Anweisungen vor inherited auf ein Feld oder eine Property eines Vorfahren zu (aufgelöst über Datei und Index; eigene Felder, Parameter und lokale Variablen zählen nicht), solange der Vorfahr noch nicht angelegt ist. missing-inherited meldet fehlendes inherited, diese Regel die Reihenfolge. Konfidenz mittel. Schnellkorrektur: inherited an das Ende des Destruktors bzw. den Anfang des Konstruktors verschieben; nicht, wenn die Argumente von inherited Create vorher gesetzte lokale Variablen verwenden.

Mit Treffer:

```pascal
destructor TExport.Destroy;
begin
  inherited;
  FDatei.Free;
end;
```

Richtig:

```pascal
destructor TExport.Destroy;
begin
  FDatei.Free;
  inherited;
end;
```

<a id="inherited-wrong-method"></a>
### inherited-wrong-method

**inherited ruft eine andere Methode** · Bug · Warnung · Gruppe Fehler finden

In der überschriebenen Methode Speichern steht inherited Laden(…) statt inherited Speichern(…), meist nach Kopieren einer Methode. Es zählen nur Aufrufe (inherited Name als Anweisung oder mit Klammern); inherited Caption ohne Klammern kann eine Property sein. Still in Konstruktoren (inherited Create(nil), CreateNew), in Methoden ohne override und wenn die Methode auch sich selbst im Vorfahren aufruft (inherited; bzw. inherited Speichern), denn dann ist der andere Aufruf gewollt. Paare aus der Option allowed bleiben still. Konfidenz hoch. Schnellkorrektur: den Namen durch den eigenen ersetzen, wenn die Zahl der Argumente zu ihren Parametern passt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowed` | string-list | `[]` | Erlaubte Paare "Methode>geerbte Methode", Muster mit * und ?, z. B. "Speichern>Pruefen". |

Mit Treffer:

```pascal
procedure TKundenForm.Speichern;
begin
  inherited Laden;
  Protokollieren;
end;
```

Richtig:

```pascal
procedure TKundenForm.Speichern;
begin
  inherited Speichern;
  Protokollieren;
end;
```

<a id="getter-side-effect"></a>
### getter-side-effect

**Getter verändert den Zustand** · Code Smell · Warnung · Gruppe Fehler finden

Die read-Methode einer Property weist Feldern oder Properties des eigenen Objekts zu (FAbrufe, Self.FWert, auch geerbte Felder), ruft Inc/Dec/Include/Exclude darauf auf oder übergibt ein neu angelegtes Objekt an eine Methode eines Felds (FListe.Add(TEintrag.Create)). Der Debugger wertet Getter beim Anzeigen aus und ändert so den Zustand. Lazy-Initialisierung ist erlaubt: Ein umschließendes if prüft etwas, das sein Zweig zuweist (if FListe = nil then FListe := …, if Result = nil then … FListe := Result, if not FGeladen then … FGeladen := True). Still bei lokalen Variablen mit dem Namen eines Felds, Result, Methoden ohne Property und anonymen Methoden. Eine Meldung je Getter und Feld. Konfidenz mittel. Keine Schnellkorrektur.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowLazyInit` | boolean | `true` | Lazy-Initialisierung im Getter erlauben (if FListe = nil then FListe := …). |

Mit Treffer:

```pascal
function TZaehler.GetWert: Integer;
begin
  Inc(FAbrufe);
  Result := FWert;
end;
```

Richtig:

```pascal
function TZaehler.GetWert: Integer;
begin
  Result := FWert;
end;
```

<a id="equals-without-gethashcode"></a>
### equals-without-gethashcode

**Equals ohne GetHashCode** · Bug · Warnung · Gruppe Fehler finden

Eine Klasse überschreibt Equals, aber nicht GetHashCode (oder umgekehrt). In TDictionary und THashSet mit Standard-Comparer finden gleiche Objekte sich dann nicht. Still, wenn ein Vorfahr das Gegenstück überschreibt, wenn die Vorfahrenkette nicht vollständig bekannt ist und bei Equals ohne override. Gilt ebenso für Records der Datei mit class operator Equal, die als Schlüssel von TDictionary, TObjectDictionary, THashSet oder TMultiMap ohne Comparer dienen (Create ohne Argumente oder nur mit Konstanten wie Kapazität oder Besitz): Der Standard-Comparer vergleicht Records Byte für Byte, was nur bei Feldern vom Typ string, Variant, Gleitkomma, Interface oder TArray falsch ist; Records mit nur ordinalen Feldern bleiben still. Konfidenz hoch. Schnellkorrektur für Klassen: GetHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals mit THashBobJenkins über die eigenen Felder umsetzen, die Equals vergleicht (ohne Groß-/Kleinschreibung über LowerCase, wenn Equals SameText nutzt), System.Hash in uses ergänzen.

Mit Treffer:

```pascal
  TKundenNr = class
    function Equals(Obj: TObject): Boolean; override;
  end;
```

Richtig:

```pascal
  TKundenNr = class
    function Equals(Obj: TObject): Boolean; override;
    function GetHashCode: Integer; override;
  end;
```

<a id="destroy-called-directly"></a>
### destroy-called-directly

**Destroy statt Free aufgerufen** · Bug · Warnung · Gruppe Fehler finden

Obj.Destroy wird direkt als Anweisung aufgerufen. Ist Obj nil, knallt der Aufruf; Free prüft vorher auf nil und ist der übliche Weg, ein Objekt freizugeben. inherited Destroy und Aufrufe eines Destruktors mit Argumenten sind ausgenommen. Konfidenz hoch. Schnellkorrektur: aus Destroy wird Free.

Mit Treffer:

```pascal
Verbindung.Destroy;
```

Richtig:

```pascal
Verbindung.Free;
```

<a id="managed-type-raw-memory"></a>
### managed-type-raw-memory

**FillChar, Move oder GetMem auf verwaltete Typen** · Bug · Fehler · Gruppe Fehler finden

FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem oder FreeMem auf eine Variable, deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält (Records, statische Arrays und Aliasse werden in der Datei und im Index aufgelöst). Referenzzähler werden überschrieben oder übergangen: Lecks, doppelte Freigabe, Zugriffsverletzungen. Geprüft werden nur einfache Variablen (X, @X, P^); Array-Elemente wie S[1] und Typen, die sich nicht auflösen lassen, bleiben still. Konfidenz hoch. Schnellkorrekturen: aus FillChar(X, SizeOf(X), 0) wird X := Default(T), aus Move(A, B, SizeOf(T)) wird B := A, aus GetMem(P, SizeOf(T)) wird New(P) und aus FreeMem(P) wird Dispose(P); sonst helfen Initialize und Finalize.

Mit Treffer:

```pascal
FillChar(Adresse, SizeOf(Adresse), 0);
```

Richtig:

```pascal
Adresse := Default(TAdresse);
```

<a id="threadvar-managed"></a>
### threadvar-managed

**threadvar mit verwaltetem Typ** · Bug · Warnung · Gruppe Threads

Delphi finalisiert threadvar-Variablen nicht. Ein String, Interface, dynamisches Array oder Variant in einer threadvar (auch in einem Record oder statischen Array) leckt in jedem Thread, der endet. Typen werden in der Datei und im Index aufgelöst. Konfidenz hoch. Keine Schnellkorrektur: den Wert am Thread-Ende freigeben (etwa in TThread.Execute auf '' bzw. nil setzen) oder stattdessen einen Zeiger bzw. Puffer fester Größe ablegen.

Mit Treffer:

```pascal
threadvar
  LetzteMeldung: string;
```

Richtig:

```pascal
threadvar
  LetzteMeldung: PChar;
```

<a id="pchar-of-temporary"></a>
### pchar-of-temporary

**PChar auf einen temporären String** · Bug · Warnung · Gruppe Fehler finden

PChar (PWideChar, PAnsiChar) eines temporären Strings, etwa einer Verkettung mit einem String (S + '.bak') oder eines Funktionsergebnisses (IntToStr(N)), wird in einer Variablen, einem Feld oder Result gemerkt oder an PostMessage, PostThreadMessage, SendNotifyMessage oder SendMessageCallback übergeben (auch hinter LPARAM(…)). Der temporäre String wird nach der Anweisung freigegeben, der Zeiger zeigt dann ins Leere. Die Übergabe an einen gewöhnlichen Aufruf wie CopyFile ist in Ordnung. Konfidenz hoch. Schnellkorrektur für lokale Variablen: das Zwischenergebnis in eine Inline-String-Variable legen.

Mit Treffer:

```pascal
Ziel := PChar(Pfad + '.bak');
CopyFile(PChar(Pfad), Ziel, False);
```

Richtig:

```pascal
var ZielText: string := Pfad + '.bak';
Ziel := PChar(ZielText);
CopyFile(PChar(Pfad), Ziel, False);
```

<a id="out-param-read"></a>
### out-param-read

**out-Parameter gelesen, bevor er gesetzt ist** · Bug · Warnung · Gruppe Fehler finden

Ein out-Parameter wird auf einem Weg durch den Kontrollfluss gelesen, bevor die Routine ihn setzt. Bei verwalteten Typen (string, Interfaces, dynamische Arrays, Variant) hat der Aufrufer ihn schon geleert, der alte Wert ist weg; bei anderen Typen ist der Wert undefiniert. Gemeint war meist var. Verwendungen, denen der Kontrollflussgraph nicht folgen kann (Übergabe an eine Routine, Setzen eines Felds, @Param), bleiben still. Konfidenz hoch. Schnellkorrektur: aus out wird var in Implementierung und Deklaration.

Mit Treffer:

```pascal
procedure Anhaengen(out Text: string);
begin
  Text := Text + sLineBreak + 'Ende';
end;
```

Richtig:

```pascal
procedure Anhaengen(var Text: string);
begin
  Text := Text + sLineBreak + 'Ende';
end;
```

<a id="noreturn-returns"></a>
### noreturn-returns

**noreturn-Routine kann normal zurückkehren** · Bug · Warnung · Gruppe Fehler finden

Eine mit noreturn markierte Routine (ab Delphi 13) darf nur über raise, Abort, Halt, RunError oder den Aufruf einer anderen noreturn-Routine enden. Erreicht ein Weg das Ende des Rumpfs oder ein Exit, kehrt sie normal zurück; der Compiler hat den Code nach dem Aufruf weggelassen, das Verhalten ist undefiniert. Die Direktive zählt an der Implementierung und an der Deklaration (interface, Klasse). Aufrufe, deren Ziel weder die Datei, die Standardroutinen noch der Symbolindex kennt, könnten selbst noreturn sein und beenden den Weg ebenfalls; gemeldet werden also nur Wege aus bekannten Anweisungen. Unvollständiger Kontrollfluss (asm, Syntaxfehler) bleibt still. Exit wird an der Anweisung gemeldet, das Ende des Rumpfs am Routinennamen. Konfidenz hoch. Keine Schnellkorrektur.

Mit Treffer:

```pascal
procedure Fehler(const AText: string); noreturn;
begin
  if AText <> '' then
    raise EImport.Create(AText);
end;
```

Richtig:

```pascal
procedure Fehler(const AText: string); noreturn;
begin
  if AText = '' then
    raise EImport.Create('Unbekannter Fehler');
  raise EImport.Create(AText);
end;
```

<a id="stringlist-unsorted"></a>
### stringlist-unsorted

**Find oder Duplicates auf einer unsortierten TStringList** · Bug · Warnung · Gruppe Fehler finden

Find auf einer TStringList oder THashedStringList, die in der Unit erzeugt, aber nie sortiert wird: Find sucht binär und liefert auf einer unsortierten Liste falsche Ergebnisse. Ebenso wirkt Duplicates := dupIgnore oder dupError nur bei sortierten Listen. Als sortiert gelten Sorted := True (oder jeder Wert außer False), Sort, CustomSort, Create(Duplicates, True, ...) und with Liste do. Eine Liste, die an eine Routine übergeben oder einer anderen Variablen zugewiesen wird, bleibt still. Lokale Variablen gelten je Routine, Felder in der ganzen Unit. Konfidenz mittel. Schnellkorrekturen: Sorted := True nach dem Erzeugen (nicht, wenn die Liste Insert, Move oder Exchange benutzt, die bei sortierten Listen eine Ausnahme auslösen) und bei if Liste.Find(S, I) then die Form I := Liste.IndexOf(S) mit if I >= 0.

Mit Treffer:

```pascal
Namen := TStringList.Create;
Namen.LoadFromFile(Datei);
if Namen.Find(Suche, Index) then
  Namen.Delete(Index);
```

Richtig:

```pascal
Namen := TStringList.Create;
Namen.Sorted := True;
Namen.LoadFromFile(Datei);
if Namen.Find(Suche, Index) then
  Namen.Delete(Index);
```

<a id="writeln-in-gui-app"></a>
### writeln-in-gui-app

**Writeln in einem Programm ohne Konsole** · Bug · Warnung · Gruppe Fehler finden

Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem Programm ohne Konsole: zur Laufzeit löst Writeln EInOutError aus (E/A-Fehler 105), Readln E/A-Fehler 104. Die Anwendungsart kommt aus DCC_ConsoleTarget der .dproj und {$APPTYPE CONSOLE} der .dpr (auch in {$IFDEF}); Units werden nur geprüft, wenn sie zum geladenen Projekt gehören, eine .dpr ohne Projekt für sich. Bibliotheken und Packages bleiben still. Ausgenommen sind Aufrufe mit einer Textdatei als erstem Argument, Aufrufe unter if IsConsole, gleichnamige Routinen der Unit und Read/Write in Methoden (TStream.Read). Konfidenz hoch. Schnellkorrektur für Write und Writeln: Ersatz durch OutputDebugString(PChar(...)) und Winapi.Windows im uses; Zahlen und Boolean über IntToStr, FloatToStr und BoolToStr. Die Option replacement setzt ein anderes Ziel, z. B. Log.Info oder Logger.Log(TLogLevel.Info, %s). Keine Korrektur bei Breitenangaben (X:5) oder Argumenten unbekannten Typs.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `replacement` | string | `"OutputDebugString"` | Ersatz für Write und Writeln in der Schnellkorrektur; %s steht für den Text. |

Mit Treffer:

```pascal
procedure TfrmHaupt.btnStartClick(Sender: TObject);
begin
  Writeln('Start: ', TimeToStr(Now));
end;
```

Richtig:

```pascal
procedure TfrmHaupt.btnStartClick(Sender: TObject);
begin
  OutputDebugString(PChar('Start: ' + TimeToStr(Now)));
end;
```

<a id="exception-in-destructor"></a>
### exception-in-destructor

**raise im Destruktor** · Bug · Warnung · Gruppe Exceptions

raise in einem Destruktor (auch class destructor), das kein except im Destruktor abfängt. Die Ausnahme bricht die Freigabe ab: inherited Destroy läuft nicht mehr, das Objekt bleibt halb freigegeben, und in einem finally des Aufrufers überdeckt sie die ursprüngliche Ausnahme. Ein raise im try-Teil eines try..except ist abgefangen; raise im except- oder finally-Teil, auch ein erneutes raise;, wird gemeldet. Eingebettete Routinen und anonyme Methoden sind ausgenommen. Aufrufen, die ihrerseits auslösen, folgt die Regel nicht. Konfidenz hoch. Keine Schnellkorrektur: den Zustand protokollieren oder ohne Ausnahme freigeben.

Mit Treffer:

```pascal
destructor TSitzung.Destroy;
begin
  if FOffen then
    raise ESitzung.Create('Sitzung noch offen');
  inherited;
end;
```

Richtig:

```pascal
destructor TSitzung.Destroy;
begin
  if FOffen then
    Schliessen;
  inherited;
end;
```

<a id="duplicate-condition"></a>
### duplicate-condition

**Doppelte Bedingung oder gleiche Zweige** · Bug · Warnung · Gruppe Fehler finden

Dieselbe Bedingung zweimal in einer if … else if-Kette (der spätere Zweig wird nie erreicht), gleiche then- und else-Zweige, derselbe Operand zweimal in einer and-, or- oder xor-Kette und Vergleiche eines Ausdrucks mit sich selbst (X = X, X < X). Meist ein Kopierfehler. Verglichen werden die Token ohne Leerraum, Kommentare und Groß-/Kleinschreibung. Ketten mit Aufrufen, die Zustand ändern können (alles außer SameText, Length, Assigned, Pos und ähnlichen reinen Funktionen, dazu Read, Next, Pop, Random …), bleiben still, ebenso Gleitkomma-Vergleiche mit sich selbst (NaN-Prüfung X <> X) und Vergleiche über Klassenmitglieder wie TFoo.Shared = TFoo.Shared. Konfidenz hoch. Keine Schnellkorrektur; die Aktion springt zum ersten Vorkommen.

Mit Treffer:

```pascal
if Betrag > 1000 then
  Stufe := 3
else if Betrag > 500 then
  Stufe := 2
else if Betrag > 1000 then
  Stufe := 1;
```

Richtig:

```pascal
if Betrag > 1000 then
  Stufe := 3
else if Betrag > 500 then
  Stufe := 2
else if Betrag > 100 then
  Stufe := 1;
```

<a id="case-missing-enum-value"></a>
### case-missing-enum-value

**case über Aufzählung ohne alle Werte** · Bug · Warnung · Gruppe Fehler finden

Ein case über einen Aufzählungstyp ohne else deckt nicht alle Werte ab; ein später ergänzter Wert fällt still durch. Die Meldung nennt die fehlenden Werte. Den Typ des Selektors (Variable, Parameter, Feld oder Kette A.B) liefert die Namensauflösung, die Werte der Index bzw. die Unit selbst; Aliase werden verfolgt. Bereiche (bsNeu..bsBezahlt) und Listen zählen als vorhanden. Selektoren mit Aufrufen, Ganzzahlen und unbekannte Typen bleiben still. Mit der Option requireElse wird auch ein case mit else gemeldet. Konfidenz hoch. Schnellkorrektur „Fehlende Werte ergänzen (n)“ ergänzt leere Zweige in Deklarationsreihenfolge vor else bzw. end, mit Typpräfix, wenn die Marken einen tragen ({$SCOPEDENUMS ON}).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `requireElse` | boolean | `false` | Auch case-Anweisungen mit else melden, wenn Werte fehlen. |

Mit Treffer:

```pascal
case Bestellung.Status of
  bsNeu: Anlegen;
  bsBezahlt: Versenden;
end;
```

Richtig:

```pascal
case Bestellung.Status of
  bsNeu: Anlegen;
  bsBezahlt: Versenden;
  bsStorniert: ;
  bsZurueck: ;
end;
```

<a id="pair-without-finally"></a>
### pair-without-finally

**Paarige Aufrufe ohne try/finally** · Bug · Warnung · Gruppe Fehler finden

Verallgemeinert lock-without-finally (dessen Sperrpaare dort bleiben) auf andere Paare: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (auch in if FindFirst(...) = 0 then begin ... end), Reset, Rewrite oder Append/CloseFile, GetMem oder AllocMem/FreeMem und Screen.Cursor := ... mit einem späteren Screen.Cursor := .... Gemeldet wird, wenn das Schließen später ungeschützt in derselben Anweisungsliste steht und mindestens eine Anweisung dazwischen liegt; eine Exception dort lässt den Zustand hängen. Beide Aufrufe müssen denselben Empfänger bzw. dasselbe Argument haben. Überlappende Paare meldet die Regel zusammen. Konfidenz hoch. Schnellkorrektur: die Anweisungen dazwischen in try/finally mit den schließenden Aufrufen einschließen, wenn diese direkt aufeinander folgen. Die Option pairs ergänzt eigene Paare.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `pairs` | json | `[]` | Weitere Paare als [{"open": "Einfrieren", "close": "Auftauen"}], wahlweise mit openArg/closeArg. |

Mit Treffer:

```pascal
Screen.Cursor := crHourGlass;
Tabelle.DisableControls;
Importieren;
Tabelle.EnableControls;
Screen.Cursor := crDefault;
```

Richtig:

```pascal
Screen.Cursor := crHourGlass;
Tabelle.DisableControls;
try
  Importieren;
finally
  Tabelle.EnableControls;
  Screen.Cursor := crDefault;
end;
```

<a id="processmessages-in-loop"></a>
### processmessages-in-loop

**Application.ProcessMessages in Schleifen** · Code Smell · Hinweis · Gruppe Threads

Application.ProcessMessages in einer for-, while- oder repeat-Schleife oder direkt in einem Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für Wiedereintritt: Der Benutzer klickt erneut, schließt das Formular oder startet den Vorgang doppelt. Aufrufe in anonymen Methoden überlässt die Regel thread-vcl-access; ProcessMessages anderer Objekte zählt nicht. Konfidenz mittel, keine Schnellkorrektur: die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren. Die Option allowIn nennt Methoden, in denen es erlaubt ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowIn` | string-list | `[]` | Methoden, in denen ProcessMessages erlaubt ist, als Name oder Klasse.Name. |

Mit Treffer:

```pascal
while not Done do
begin
  Step;
  Application.ProcessMessages;
end;
```

Richtig:

```pascal
StartButton.Enabled := False;
TTask.Run(
  procedure
  begin
    while not Done do
      Step;
    TThread.Queue(nil, procedure begin StartButton.Enabled := True; end);
  end);
```

<a id="unchecked-conversion"></a>
### unchecked-conversion

**Umwandlung einer Benutzereingabe ohne Prüfung** · Bug · Hinweis · Gruppe Fehler finden

StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime oder StrToCurr direkt auf einer Benutzereingabe (Edit.Text, Grid.Cells[...], Memo.Lines[...], auch in Trim) außerhalb des try-Teils eines try/except. Eine Fehleingabe löst EConvertError mit englischer Meldung aus. try/finally gilt nicht als Schutz. Konfidenz mittel. Schnellkorrektur für X := StrToInt(Edit.Text); als eigene Anweisung, wenn X eine Variable oder ein Feld des passenden Typs ist: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create('X ist keine Zahl'). format-without-settings meldet zusätzlich landesabhängige Umwandlungen ohne TFormatSettings. Die Optionen functions und sources wählen die geprüften Umwandlungen und die Eigenschaften, die als Eingabe gelten.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `functions` | string-list | `["StrToInt","StrToInt64","StrToFloat","StrToDate","StrToDateTime","StrToCurr"]` | Geprüfte Umwandlungen. |
| `sources` | string-list | `["Text","Cells","Lines"]` | Eigenschaften, die als Benutzereingabe gelten. |

Mit Treffer:

```pascal
Menge := StrToInt(edtMenge.Text);
```

Richtig:

```pascal
if not TryStrToInt(edtMenge.Text, Menge) then
  raise EConvertError.Create('Menge ist keine Zahl');
```

<a id="dictionary-get-without-check"></a>
### dictionary-get-without-check

**Dictionary-Zugriff ohne Prüfung des Schlüssels** · Bug · Hinweis · Gruppe Fehler finden

Dict[Key] bzw. Dict.Items[Key] wird auf einem TDictionary oder TObjectDictionary (auch über einen Typalias der Datei) gelesen, obwohl weder ContainsKey noch TryGetValue denselben Schlüssel vorher in der Routine geprüft hat. Still bleibt die Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue, TryAdd, Dict[K] := ...) oder der Schlüssel aus Keys bzw. den Paaren stammt (for K in Dict.Keys, Namen := Dict.Keys.ToArray, for Pair in Dict mit K := Pair.Key). Fehlt der Schlüssel, folgt EListError. Konfidenz mittel. Schnellkorrektur für X := Dict[Key]; als eigene Anweisung, wenn X eine Variable vom Wertetyp ist: if not Dict.TryGetValue(Key, X) then X := 0 (bzw. '', False, Default(T)).

Mit Treffer:

```pascal
Preis := Preise[Artikel.Nummer];
```

Richtig:

```pascal
if not Preise.TryGetValue(Artikel.Nummer, Preis) then
  Preis := 0;
```

<a id="shadowed-name"></a>
### shadowed-name

**Lokaler Name verdeckt Feld oder Property** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Parameter, eine lokale oder Inline-Variable heißt wie ein Feld oder eine Property der Klasse (auch geerbt und dort sichtbar, aufgelöst über die Datei und den Symbolindex) oder wie eine globale Variable der Unit, die vor der Routine deklariert ist. In Formularmethoden besonders tückisch: Caption, Name, Tag, Left. Steht die VCL nicht im Index, kennt die Regel die Mitglieder von TComponent und TControl, wenn die Vorfahrenkette an einer VCL-Grundklasse endet. Parameter von Ereignis-Handlern (mit Sender) bleiben außen vor, weil der Ereignistyp die Signatur vorgibt. Konfidenz hoch. Schnellkorrektur: in der Routine in AName (Parameter, auch in der Deklaration) bzw. LName (lokale Variable) umbenennen; setzt die Projektdatei .atlas Präfixe (naming), gelten diese, z. B. mName. Die Option ignore nennt Namensmuster, die nie gemeldet werden (Vorgabe Sender, Value).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `["Sender","Value"]` | Namensmuster (* und ?), die nie gemeldet werden. |

Mit Treffer:

```pascal
procedure TfrmKunde.Laden(const Caption: string);
begin
  Caption := Caption + ' (geladen)';
end;
```

Richtig:

```pascal
procedure TfrmKunde.Laden(const ACaption: string);
begin
  Caption := ACaption + ' (geladen)';
end;
```

<a id="naming-prefix"></a>
### naming-prefix

**Name ohne das Präfix seiner Art** · Code Smell · Hinweis · Gruppe Stil und Metriken

Einer lokalen Variable (auch Inline und for var), einem Feld (auch class var), einem Parameter oder einer Konstante (const, auch lokal, in Klassen und Inline; nicht resourcestring) fehlt das Präfix ihrer Art. Standard: lokal m, Feld F, Parameter A, Konstante c; hinter einem Präfix, das auf einen Buchstaben endet, folgt ein Großbuchstabe oder eine Ziffer (mIndex, nicht menu). Globale Variablen prüft die Regel nicht. Je Art kommt das Präfix aus der Option in atlas.json, sonst aus der Projektdatei .atlas (naming, auch constant), sonst der Standard; ein leerer Wert schaltet die Art ab. Standardmäßig aus: Die Regel läuft nur, wenn atlas.json sie einschaltet. Ausnahmen: Schleifenzähler aus einem Buchstaben, Sender, Self und Result, Namen nach ignore, published-Felder und Felder vor dem ersten Sichtbarkeitsabschnitt eines Formulars, Frames oder Datenmoduls (Komponenten), Parameter von Methoden mit override oder message, von published-Methoden, von Ereignis-Handlern (ein Parameter heißt Sender) und von Methoden, die eine Interface-Methode erfüllen (in der Datei oder im Symbolindex; unbekanntes Interface: still). Parameter werden nur an der Deklaration gemeldet. Schnellkorrektur: in den erwarteten Namen umbenennen, in der Routine bzw. im Block ab einer Inline-Deklaration, bei Parametern auch in Deklaration und Implementierung, bei privaten Feldern und Klassenkonstanten in der Klasse und ihren Methoden (auch Self.Name und TTyp.Name), bei Konstanten der implementation in der ganzen Unit. Keine Korrektur, wenn der neue Name dort schon vorkommt, wo umbenannt wird (Routine samt Parameterliste, bei Feldern die Klasse und ihre Methoden, bei Konstanten der implementation die Datei), der Bereich with enthält, eine verschachtelte Routine den Namen neu deklariert oder der Name außerhalb der Datei sichtbar ist. Läuft die Regel, bilden andere Korrekturen und Refactorings neue Namen mit diesen Präfixen (Konstante einführen → cNewConstant, Variable einführen und with auflösen → mValue, Parameter von „Methode anlegen“ → APreis), damit die Regel sie nicht gleich wieder meldet.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `local` | string | `"m"` | Präfix lokaler Variablen; leer = nicht prüfen. |
| `field` | string | `"F"` | Präfix von Feldern; leer = nicht prüfen. |
| `parameter` | string | `"A"` | Präfix von Parametern; leer = nicht prüfen. |
| `constant` | string | `"c"` | Präfix von Konstanten; leer = nicht prüfen. |
| `ignore` | string-list | `[]` | Namensmuster (* und ?), die nie gemeldet werden, z. B. Felder von API-Records. |

Mit Treffer:

```pascal
procedure TKunde.Laden(const Datei: string);
var
  Zeilen: TStringList;
begin
end;
```

Richtig:

```pascal
procedure TKunde.Laden(const ADatei: string);
var
  mZeilen: TStringList;
begin
end;
```

<a id="boolean-assign-if"></a>
### boolean-assign-if

**if, das nur True oder False zuweist** · Code Smell · Hinweis · Gruppe Stil und Metriken

if B then X := True else X := False (auch mit begin/end und vertauschten Werten), if B then Exit(True) else Exit(False) sowie if B then Exit(True); gefolgt von Exit(False); lassen sich direkt schreiben. Ergänzt bool-compare. Konfidenz hoch. Schnellkorrektur: X := B, X := not B bzw. Exit(B); Verneinungen werden vereinfacht (aus not B wird B), zusammengesetzte Bedingungen eingeklammert. Ohne Korrektur, wenn Kommentare im if stehen.

Mit Treffer:

```pascal
if Betrag > 0 then
  Result := True
else
  Result := False;
```

Richtig:

```pascal
Result := Betrag > 0;
```

<a id="case-insensitive-compare"></a>
### case-insensitive-compare

**Vergleich über UpperCase oder LowerCase** · Code Smell · Hinweis · Gruppe Performance

UpperCase(A) = UpperCase(B), LowerCase(A) <> 'x', AnsiUpperCase(...) oder A.ToUpper = B.ToUpper erzeugt zwei Strings für einen Vergleich. SameText (AnsiSameText bei den Ansi-Funktionen und den Unicode-String-Helfern) ist kürzer und schneller. Ein Literal zählt nur, wenn die Umwandlung es nicht ändert; UpperCase(A) = LowerCase(B) und UpperCase(A) = 'ja' bleiben unberührt, weil das andere Fehler sind. Ersetzt nicht die String-Helper-Modernisierung aus #71. Konfidenz hoch. Schnellkorrektur: SameText(A, B) bzw. not SameText(A, B).

Mit Treffer:

```pascal
if UpperCase(Land) = UpperCase(Standard) then
```

Richtig:

```pascal
if SameText(Land, Standard) then
```

<a id="magic-number"></a>
### magic-number

**Zahl ohne Namen im Code** · Code Smell · Hinweis · Gruppe Stil und Metriken

Zahlenliterale (dezimal, $hex, Gleitkomma, mit Vorzeichen) in Anweisungen, außerhalb von const-Abschnitten, Typen, Array-Grenzen und Teilbereichen. Erlaubte Werte sind einstellbar; DFM-Koordinaten und Tests lassen sich über exclude ausnehmen. Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur: Konstante einführen (#50) im const-Abschnitt der Routine.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowed` | number-list | `[0,1,-1,2,10,100]` | Zahlen, die nie gemeldet werden. |

Mit Treffer:

```pascal
if Tage > 42 then
  Mahnen;
```

Richtig:

```pascal
const
  Mahnfrist = 42;
...
if Tage > Mahnfrist then
  Mahnen;
```

<a id="line-length"></a>
### line-length

**Zeile zu lang** · Code Smell · Hinweis · Gruppe Stil und Metriken

Zeilen über der Grenze max (Vorgabe 120 Zeichen, passend zu den Linealen aus #710). Tabs zählen bis zur nächsten Tabstelle nach format.indentSize. Zeilen, die nur wegen eines Strings oder, mit ignoreComments, eines Kommentars zu lang sind, werden nicht gemeldet. Zeilen über 1023 Zeichen meldet die Regel unabhängig von max immer als Fehler, weil der Compiler dort abbricht (F2069). Standard aus. Schnellkorrektur: Zeile umbrechen hinter Kommas bzw. vor zweistelligen Operatoren, wenn die Stücke danach passen.

Entspricht der Compilermeldung `F2069`.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `120` | Höchstlänge einer Zeile in Zeichen. |
| `ignoreStrings` | boolean | `true` | Zeilen, die nur wegen eines Strings zu lang sind, nicht melden. |
| `ignoreComments` | boolean | `false` | Zeilen, die nur wegen eines Kommentars zu lang sind, nicht melden. |

Mit Treffer:

```pascal
Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, Lager.Verfuegbarkeit(Artikel), Steuer.Satz(Land));
```

Richtig:

```pascal
Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, Lager.Verfuegbarkeit(Artikel),
  Steuer.Satz(Land));
```

<a id="metric-class-size"></a>
### metric-class-size

**Klasse mit zu vielen Membern** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Klasse hat mehr Member als der Grenzwert (Vorgabe 40): Feldnamen, Methoden, Properties mit eigenem Typ und class var. Properties, die nur die Sichtbarkeit anheben (property Align;), und geschachtelte Typen zählen nicht; eine geschachtelte Klasse wird für sich gemessen. Erscheint auch in der Metrik-Linse über der Klasse. Die Klasse aufteilen oder Teile in Hilfsklassen auslagern; „Klasse in eigene Unit verschieben“ (#103) hilft, wenn auch die Unit voll ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `40` | Höchstzahl der Member je Klasse. |

Mit Treffer:

```pascal
type
  TfrmHaupt = class(TForm)
    { 87 members }
  end;
```

Richtig:

```pascal
type
  TfrmHaupt = class(TForm)
    { 25 members; data access in TKundenDaten }
  end;
```

<a id="metric-unit-length"></a>
### metric-unit-length

**Unit zu lang** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Unit hat mehr Zeilen als der Grenzwert (Vorgabe 2000), gezählt bis zum abschließenden end. Gemessen werden nur Units, keine Programme oder Packages. Erscheint auch in der Metrik-Linse über dem Unit-Namen. Klassen mit „Klasse in eigene Unit verschieben“ (#103) auslagern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `2000` | Höchstzahl der Zeilen je Unit. |

Mit Treffer:

```pascal
unit Kasse.Haupt;  { 2140 lines }
```

Richtig:

```pascal
unit Kasse.Haupt;  { 900 lines; TBeleg in Kasse.Beleg }
```

<a id="metric-uses-count"></a>
### metric-uses-count

**Zu viele Units im uses** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Unit bindet mehr Units ein als der Grenzwert (Vorgabe 30), interface und implementation zusammen. Der Befund steht auf dem ersten uses. Programme und Bibliotheken werden nicht geprüft, weil ihr uses die Units des Projekts aufzählt. Erscheint auch in der Metrik-Linse über uses. Viele Abhängigkeiten heißen meist, dass die Unit zu viel tut; „Klasse in eigene Unit verschieben“ (#103) teilt sie.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `30` | Höchstzahl der Units in allen uses-Klauseln. |

Mit Treffer:

```pascal
uses
  { 34 units in interface and implementation }
```

Richtig:

```pascal
uses
  { 12 units; reports in Kasse.Berichte }
```

<a id="metric-inheritance-depth"></a>
### metric-inheritance-depth

**Zu tiefe Vererbung** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Klasse hat mehr eigene Vorfahren als der Grenzwert (Vorgabe 5). Vorfahren aus RTL, VCL, FMX und anderen Bibliotheken zählen nicht (am Unit-Namen oder weil der Index sie aus dem Bibliothekspfad nachgeladen hat), TObject ebenso. Vorfahren werden in der Datei und im Symbolindex gesucht. Bricht die Kette an einem unbekannten Vorfahren ab, bevor sie eine Bibliothek erreicht, ist der Wert eine Untergrenze und die Meldung sagt „mindestens“; gemeldet wird nur, wenn schon sie über der Grenze liegt. Units einer Bibliothek selbst werden nicht geprüft. Der Befund steht auf dem Klassennamen; die Metrik-Linse zeigt die Tiefe neben den Membern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `5` | Höchstens so viele eigene Vorfahren. |

Mit Treffer:

```pascal
TBasis = class(TForm) ... TStufe6 = class(TStufe5)  { 6 own ancestors }
```

Richtig:

```pascal
TStufe2 = class(TBasis)
  FDruck: IDruck;  { composition instead of more levels }
```

<a id="public-field"></a>
### public-field

**Öffentliches Feld** · Code Smell · Hinweis · Gruppe Stil und Metriken

Felder im public- oder published-Abschnitt einer Klasse. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren oder mit TObject, weil der Formulardesigner dort seine Felder anlegt. Records sind ausgenommen, außer mit includeRecords; class var wird nicht gemeldet. Standard aus. Schnellkorrektur: Feld kapseln legt das Feld als FName in einen private-Abschnitt am Ende der Klasse und ergänzt im alten Abschnitt property Name read FName write FName; Zugriffe von außen bleiben gültig.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `includeRecords` | boolean | `false` | Auch Felder von Records melden. |

Mit Treffer:

```pascal
TKunde = class
public
  Name: string;
end;
```

Richtig:

```pascal
TKunde = class
private
  FName: string;
public
  property Name: string read FName write FName;
end;
```

<a id="legacy-tlist"></a>
### legacy-tlist

**Ungenerische Liste mit Cast** · Code Smell · Information · Gruppe Stil und Metriken

Eine ungenerische TList (System.Classes) oder TObjectList (System.Contnrs), deren Elemente mit Cast gelesen werden: T(Liste[I]), T(Liste.Items[I]), T(Liste.First), Liste[I] as T usw. TList<T> und TObjectList<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Die Regel meldet je Liste einmal, an ihrer Deklaration, wenn sie in der Datei steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Listentyp und Zieltyp sicher findet; Casts auf Pointer zählen nicht. Standard aus; für Code, der noch mit alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur (#1105): wandelt die Liste in einem Schritt in TList<T> bzw. TObjectList<T> um: Deklaration, jedes Create (Argumente bleiben), jeden Cast und System.Generics.Collections im uses; Contnrs entfällt, wenn nichts anderes es braucht. Nur wenn alle Lesezugriffe denselben Cast haben, kein Mitglied ohne generisches Gegenstück vorkommt (Sort mit TListSortCompare, Assign mit TListAssignOp, List), keine Pointer- oder Integer-Werte in der Liste stehen, Add, Extract, Remove und IndexOf T bekommen und die Liste nicht weitergegeben wird. Ist die Liste außerhalb der Unit sichtbar, schreibt die Korrektur die anderen Units der Projektgruppe mit um oder entfällt; solche Korrekturen wendet „Alle korrigieren“ (source.fixAll) nie an. Sonst nennt der Befund-Hover den Grund. Stapel und Warteschlangen: legacy-stack-queue.

Mit Treffer:

```pascal
FPositionen: TList;
...
Pos := TPosition(FPositionen[I]);
```

Richtig:

```pascal
FPositionen: TList<TPosition>;
...
Pos := FPositionen[I];
```

<a id="legacy-stack-queue"></a>
### legacy-stack-queue

**Ungenerischer Stapel oder ungenerische Warteschlange mit Cast** · Code Smell · Information · Gruppe Stil und Metriken

Ein ungenerischer TStack, TQueue, TObjectStack oder TObjectQueue (System.Contnrs), dessen Elemente mit Cast gelesen werden: T(Stapel.Pop), T(Stapel.Peek), Schlange.Pop as T usw. TStack<T>, TQueue<T>, TObjectStack<T> und TObjectQueue<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Wie legacy-tlist meldet die Regel je Stapel bzw. Warteschlange einmal, an der Deklaration, wenn sie in der Datei steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Typ und Zieltyp sicher findet; Casts auf Pointer zählen nicht. Standard aus; für Code, der noch mit alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur: wandelt in einem Schritt um wie legacy-tlist; bei Warteschlangen wird Push zu Enqueue und Pop zu Dequeue. TObjectStack<T> und TObjectQueue<T> besitzen ihre Objekte, die Contnrs-Klassen nicht: Die Korrektur erzeugt sie deshalb mit Create(False) und liest mit Extract, weil Pop und Dequeue dort Prozeduren sind, die das Objekt freigeben. Ohne Create in der Unit, mit verschiedenen Casts oder mit Mitgliedern ohne generisches Gegenstück (AtLeast) gibt es keine Korrektur; der Befund-Hover nennt den Grund.

Mit Treffer:

```pascal
FOffen: TObjectStack;
...
Knoten := TKnoten(FOffen.Pop);
```

Richtig:

```pascal
FOffen: TObjectStack<TKnoten>;
...
FOffen := TObjectStack<TKnoten>.Create(False);
...
Knoten := FOffen.Extract;
```

<a id="global-variable"></a>
### global-variable

**Globale Variable im interface** · Code Smell · Hinweis · Gruppe Stil und Metriken

var oder threadvar im interface-Teil einer Unit: Jede Unit, die sie einbindet, kann den Wert lesen und ändern. Die Formularvariable des Designers (frmHaupt: TfrmHaupt, bei Nachfahren von TForm, TFrame, TDataModule oder jeder Klasse einer Unit mit Formulardatei) ist ausgenommen, außer mit includeFormVariables. Standard aus. Die Variable in den implementation-Teil verschieben und eine Funktion oder Property anbieten.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `includeFormVariables` | boolean | `false` | Auch die Formularvariablen des Designers melden. |

Mit Treffer:

```pascal
interface
var
  AktuellerBenutzer: TBenutzer;
```

Richtig:

```pascal
interface
function AktuellerBenutzer: TBenutzer;
implementation
var
  GBenutzer: TBenutzer;
```

<a id="commented-out-code"></a>
### commented-out-code

**Auskommentierter Code** · Code Smell · Hinweis · Gruppe Stil und Metriken

Mindestens minLines aufeinanderfolgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar), die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen lassen. Prosa am Anfang und Ende des Blocks bleibt außen vor, mindestens die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do). XMLDoc (///) und Kommentare vor dem ersten Token (Lizenzköpfe) meldet die Regel nie. Sicherheit mittel. Die Versionsverwaltung bewahrt den alten Code auf; die Korrektur entfernt die Zeilen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `minLines` | integer | `3` | Mindestzahl aufeinanderfolgender auskommentierter Codezeilen. |

Mit Treffer:

```pascal
Speichern;
// if Kunde.Aktiv then
//   Kunde.Speichern;
// Log('gespeichert');
```

Richtig:

```pascal
Speichern;
```

<a id="default-parameter"></a>
### default-parameter

**Standardparameter statt Überladung** · Code Smell · Warnung · Gruppe Stil und Metriken

Ein Parameter mit Vorgabewert (Anzahl: Integer = 10). Für Teams, die Überladungen bevorzugen: Vorgabewerte landen beim Aufrufer im Code, ändern sich nicht mit der Bibliothek und vertragen sich schlecht mit Überladungen. Gemeldet wird einmal je Deklaration (Klassenmitglied, interface-Teil, forward oder eine Routine nur im implementation-Teil); der Rumpf zu einer Deklaration nicht noch einmal. Die Schnellkorrektur fügt vor der Deklaration je weggelassenem Standardparameter am Ende eine Überladung ein, die mit dem Vorgabewert weiterreicht, entfernt die Vorgabewerte (auch im Rumpf wiederholte) und ergänzt overload. Keine Korrektur, wenn die Signatur von außen vorgegeben ist (virtual, dynamic, abstract, override, message, external, Interface-Typen), der Name als Wert benutzt wird (@Routine, Methodenzeiger), es schon eine gleichnamige Überladung gibt, in bedingter Übersetzung oder wenn der Rumpf nicht eindeutig zu finden ist.

Mit Treffer:

```pascal
procedure Exportieren(const Datei: string; MitKopf: Boolean = True);
```

Richtig:

```pascal
procedure Exportieren(const Datei: string); overload;
procedure Exportieren(const Datei: string; MitKopf: Boolean); overload;
```

<a id="empty-routine"></a>
### empty-routine

**Leere Methode** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Methode oder Routine, deren Rumpf weder eine Anweisung noch einen Kommentar (noch eine Compiler-Direktive) enthält. Entweder fehlt der Inhalt oder die Methode kann weg. Nicht gemeldet werden virtuelle und dynamische Methoden (Ersatz für abstract in Basisklassen), Nachrichten-Handler, Methoden von Klassen mit Interfaces (der Compiler verlangt jede Interface-Methode), Ereignis-Handler, die in der Formulardatei stehen (die IDE entfernt leere beim Speichern), und Rümpfe mit Kommentar, etwa Überschreibungen, die bewusst nichts tun. Schnellkorrekturen: Kommentar zwischen begin und end einfügen; Methode entfernen (Deklaration samt XML-Doku und Rumpf) nur bei privaten Methoden und Routinen ohne Deklaration im interface-Teil, die sonst nirgends in der Datei vorkommen und keine Signatur von außen erfüllen.

Mit Treffer:

```pascal
procedure TImport.Pruefen;
begin
end;
```

Richtig:

```pascal
procedure TImport.Pruefen;
begin
  // Absichtlich leer.
end;
```

<a id="write-only-property"></a>
### write-only-property

**Property ohne read** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Property hat write, aber kein read. Sie lässt sich nicht im Objektinspektor anzeigen, nicht im Debugger lesen und verwirrt Aufrufer. Properties ohne Typ bleiben außen vor (sie veröffentlichen eine geerbte Property neu, deren read vom Vorfahren kommt), ebenso Properties mit einem Attribut aus allowAttributes (mit oder ohne Endung Attribute). Schnellkorrektur: read FName ergänzen, wenn der Typ ein Feld FName gleichen Typs deklariert. Das Lesen einer solchen Property meldet readonly-property-assigned.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowAttributes` | string-list | `[]` | Attribute, die eine Property ohne read erlauben. |

Mit Treffer:

```pascal
property Passwort: string write SetPasswort;
```

Richtig:

```pascal
property Passwort: string read FPasswort write SetPasswort;
```

<a id="xmldoc-mismatch"></a>
### xmldoc-mismatch

**XMLDoc passt nicht zur Signatur** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein ///-Kommentar passt nicht zu seiner Deklaration oder ist kein wohlgeformtes XML, wie die Compilerwarnungen W1201 bis W1208 mit eingeschalteter XML-Dokumentation. Gemeldet werden: <param> zu einem Parameter, den es nicht gibt; fehlende <param>, wenn der Block überhaupt Parameter beschreibt (wie W1208, „but other parameters do“); mit checkReturns <returns> an einer Routine ohne Ergebnis und fehlendes <returns> an einer Funktion, deren Block Parameter beschreibt. <inheritdoc/> ergänzt, was fehlt. Außerdem '<' und '&' außerhalb von Tags und Entitäten, unbekannte Entitäten, Attributwerte ohne Anführungszeichen, nicht geschlossene und überzählige Endtags sowie cref-Ziele, die es nicht gibt (W1206, nur mit Index und wenn jede Unit aus uses bekannt ist; generische Ziele, Unit-Namen und Typen mit unbekannten Vorfahren bleiben still). Mit requirePublic zusätzlich public- und published-Methoden und -Properties von Typen im interface ohne ///-Kommentar (nicht override, nicht Properties ohne Typ). Schnellkorrekturen: unbekannte <param> der Reihe nach auf die fehlenden umbenennen, die übrigen als leere Zeilen in Signaturreihenfolge ergänzen, überzählige <param> und <returns> an Prozeduren entfernen; Zeichen maskieren, Anführungszeichen setzen, Endtag ergänzen oder entfernen, ein fremdes leeres Tag wie TList<T> als Text schreiben; cref auf das ähnlichste Symbol setzen; Kommentargerüst erzeugen.

Entspricht der Compilermeldung `W1201`, `W1202`, `W1203`, `W1204`, `W1205`, `W1206`, `W1207`, `W1208`.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `requirePublic` | boolean | `false` | Öffentliche Member ohne XMLDoc melden. |
| `checkReturns` | boolean | `true` | <returns> prüfen. |

Mit Treffer:

```pascal
/// <summary>Sucht einen Kunden.</summary>
/// <param name="Nummer">Kundennummer</param>
function Suchen(const Id: Integer; Aktive: Boolean): TKunde;
```

Richtig:

```pascal
/// <summary>Sucht einen Kunden.</summary>
/// <param name="Id">Kundennummer</param>
/// <param name="Aktive"></param>
function Suchen(const Id: Integer; Aktive: Boolean): TKunde;
```

<a id="queue-nil-in-package"></a>
### queue-nil-in-package

**TThread.Queue(nil, …) in einem Package** · Bug · Warnung · Gruppe Threads

TThread.Queue(nil, …) oder TThread.ForceQueue(nil, …) in einer Unit eines Design-Time- oder Laufzeit-Packages: Der Eintrag gehört keinem Thread, beim Entladen des Packages räumt ihn niemand weg, und CheckSynchronize ruft ihn womöglich danach in fremdem Speicher auf. Package-Units erkennt die Regel über die .dpk bzw. .dproj des geladenen Projekts (eine .dpk ohne Projekt für sich). Eine Zeile mit dem Kommentar aus okMarker (Vorgabe mainthread-ok) ist ausgenommen. Sicherheit hoch. Korrektur: auf den Wrapper aus der Option wrapper umschreiben (Vorgabe TAtlasMainThread.Queue, bei ForceQueue ForceQueue); mit Klammer steht der Text so vor den übrigen Argumenten. ForceQueue mit Verzögerung bekommt keine Korrektur. Der Kommandozeilen-Linter liest die .dpk-Dateien unter dem geprüften Ordner. Leistet für jedes Plugin-Projekt dasselbe wie Tools/Check-MainThreadQueue.ps1; das Skript bleibt für Prüfungen ohne Atlas-Server.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `wrapper` | string | `"TAtlasMainThread.Queue"` | Ersatz für TThread.Queue(nil, in der Schnellkorrektur. |
| `okMarker` | string | `"mainthread-ok"` | Kommentar, der eine Zeile ausnimmt. |

Mit Treffer:

```pascal
TThread.Queue(nil,
  procedure
  begin
    FPanel.Aktualisieren;
  end);
```

Richtig:

```pascal
TAtlasMainThread.Queue(
  procedure
  begin
    FPanel.Aktualisieren;
  end);
```

<a id="ota-notifier-not-removed"></a>
### ota-notifier-not-removed

**IDE-Notifier ohne RemoveNotifier** · Bug · Warnung · Gruppe Packages und Tests

AddNotifier an IOTAServices, IOTAEditorServices, IOTAModule usw. (oder ein anderes Paar aus registerPairs), dessen Index nie an RemoveNotifier geht: Der Aufruf steht als Anweisung ohne Zuweisung, oder die Variable, der er zugewiesen wird, erhält in der Unit kein RemoveNotifier (in finalization, im Destruktor oder in Destroyed). Die IDE ruft den Notifier dann nach dem Entladen des Packages in fremdem Speicher auf. Register…-Aufrufe in der Prozedur Register sind ausgenommen: Diese Wizards entfernt die IDE selbst. Sicherheit mittel. Korrektur in Methoden: Index in ein Feld legen (FNotifierIndex im private-Abschnitt) und RemoveNotifier im Destruktor ergänzen, der bei Bedarf angelegt wird; in Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in finalization. Keine Korrektur, wenn der Empfänger ein Parameter oder eine lokale Variable ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `registerPairs` | json | `[{"open":"AddNotifier","close":"RemoveNotifier"},{"open":"RegisterPackageWizard","close":"RemoveWizard"}]` | Paare der Open Tools API als [{"open": "AddNotifier", "close": "RemoveNotifier"}]; ersetzt die Vorgabe. |

Mit Treffer:

```pascal
procedure Register;
begin
  (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);
end;
```

Richtig:

```pascal
var
  NotifierIndex: Integer = -1;

procedure Register;
begin
  NotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);
end;

initialization

finalization
  if NotifierIndex >= 0 then
    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);
```

<a id="dunitx-test-without-assert"></a>
### dunitx-test-without-assert

**DUnitX-Test ohne Assert** · Code Smell · Hinweis · Gruppe Packages und Tests

Eine [Test]- oder [TestCase]-Methode, die keine Prüfung aufruft, weder selbst noch über Methoden derselben Klasse oder Routinen der Unit: Sie ist immer grün. Als Prüfung zählen Aufrufe nach assertPatterns (Vorgabe Assert.*, WillRaise*, Check*), System.Assert und Aufrufe an Klassen mit Assert im Namen (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still. Sicherheit hoch. Korrekturen: Assert.Pass als Platzhalter einfügen oder zur Methode springen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `assertPatterns` | string-list | `["Assert.*","WillRaise*","Check*"]` | Aufrufe, die als Prüfung zählen, als Muster mit * und ?; ersetzt die Vorgabe. |

Mit Treffer:

```pascal
[Test]
procedure TImportTests.LeereDateiWirdGelesen;
begin
  FImport.Laden('leer.csv');
end;
```

Richtig:

```pascal
[Test]
procedure TImportTests.LeereDateiWirdGelesen;
begin
  FImport.Laden('leer.csv');
  Assert.AreEqual(0, FImport.Anzahl);
end;
```

<a id="event-call-without-assigned"></a>
### event-call-without-assigned

**Ereignis ohne Assigned-Prüfung aufgerufen** · Bug · Warnung · Gruppe Fehler finden

FOnChange(Self) oder OnChange(Self) wird in einer Methode der Klasse aufgerufen, ohne dass Assigned(FOnChange) oder FOnChange <> nil den Aufruf schützt: Ohne Handler folgt eine Zugriffsverletzung. Ereignisse sind Felder und Properties der Klasse mit Methodenzeiger- oder Referenztyp (procedure … of object, reference to …, TNotifyEvent, TProc/TFunc, Typen auf Event, prozedurale Typen der Unit oder des Index). Schutz: der then-Zweig einer Bedingung mit Assigned (auch while), der else-Zweig von not Assigned, "Assigned(F) and" vor dem Aufruf oder "if not Assigned(F) then Exit/raise" davor, auch über einen Merker oder eine Methode der Klasse ohne Parameter, deren Result Assigned(F) enthält. Still bleiben Felder, die ein Konstruktor mit einem Wert belegt (eingereichte Abhängigkeiten wie FReadText := AReadText), Properties darauf und gleichnamige lokale Namen. Sicherheit hoch. Korrektur: den Aufruf in "if Assigned(F) then" einschließen, wenn er als eigene Anweisung in einem Block steht.

Mit Treffer:

```pascal
procedure TZaehler.Erhoehen;
begin
  Inc(FWert);
  FOnChange(Self);
end;
```

Richtig:

```pascal
procedure TZaehler.Erhoehen;
begin
  Inc(FWert);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;
```

<a id="owned-item-freed"></a>
### owned-item-freed

**Element einer besitzenden Liste zusätzlich freigegeben** · Bug · Fehler · Gruppe Fehler finden

Ein Element einer TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True) oder eines TObjectDictionary mit doOwnsValues wird mit Free, FreeAndNil, Destroy oder DisposeOf freigegeben, direkt (Liste[I].Free, Liste.Items[I].Free) oder über eine Variable aus Liste[I], Liste.First/Last oder einer for-in-Schleife über die Liste bzw. Dictionary.Values. Die Liste gibt das Element selbst frei: bei Delete, Remove, Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben, also doppelt. Besitzend ist eine Liste, wenn die Unit sie so erzeugt (TObjectList ohne False, TObjectDictionary mit doOwnsValues) oder ohne Erzeugung als TObjectList deklariert, und kein OwnsObjects := False folgt. Extract in derselben Routine lässt die Regel schweigen. Sicherheit hoch. Korrekturen: Free entfernen (die ganze Schleife, wenn sie nur freigibt), Delete bzw. Remove statt Free, Extract statt Remove.

Mit Treffer:

```pascal
Auftraege := TObjectList<TAuftrag>.Create;
…
Auftraege[I].Free;
Auftraege.Delete(I);
```

Richtig:

```pascal
Auftraege := TObjectList<TAuftrag>.Create;
…
Auftraege.Delete(I);
```

<a id="create-without-assignment"></a>
### create-without-assignment

**Objekt erzeugt und sofort verloren** · Bug · Warnung · Gruppe Fehler finden

TStringList.Create; als eigene Anweisung: Das Objekt wird erzeugt, aber nirgends gespeichert und nie freigegeben (Speicherleck). Still bleiben Komponenten mit Owner (erstes Argument Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit einem Argument ungleich nil), Threads (geben sich mit FreeOnTerminate selbst frei), Records, unbekannte Klassen mit Argumenten und Klassen aus selfRegistering. Sicherheit hoch. Korrektur: Zuweisung an eine neue lokale Variable, die folgenden Anweisungen des Blocks in try/finally mit Free.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `selfRegistering` | string-list | `[]` | Klassen, die sich im Konstruktor selbst registrieren, als Muster mit * und ?; Create als Anweisung bleibt für sie still. |

Mit Treffer:

```pascal
procedure TImport.Starten;
begin
  TImportProtokoll.Create;
  Laden;
end;
```

Richtig:

```pascal
procedure TImport.Starten;
var
  ImportProtokoll: TImportProtokoll;
begin
  ImportProtokoll := TImportProtokoll.Create;
  try
    Laden;
  finally
    ImportProtokoll.Free;
  end;
end;
```

<a id="raw-memory-leak"></a>
### raw-memory-leak

**GetMem oder New ohne Freigabe** · Bug · Warnung · Gruppe Fehler finden

Eine lokale Variable erhält Speicher über GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, die Routine gibt ihn aber nie mit FreeMem, FreeMemory, Dispose, StrDispose oder ReallocMem(P, 0) frei, und der Zeiger verlässt die Routine nicht: weder zurückgegeben (Result, Exit) noch einer anderen Variablen oder einem Feld zugewiesen, nicht über seine Adresse (@P) weitergegeben, keiner Methode übergeben, die ihn behält (Add, Insert, Push …), nicht von einer anonymen Methode eingefangen und nicht in einer lokalen Routine benutzt. Zum Lesen oder Füllen weitergeben (Pruefsumme(P, N), Strom.ReadBuffer(P^, N)) ist erlaubt; eine Routine mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen gilt als Freigabe. Eine Freigabe ohne try/finally meldet pair-without-finally. Konfidenz mittel. Schnellkorrektur: die folgenden Anweisungen des Blocks in try … finally mit der passenden Freigabe einschließen.

Mit Treffer:

```pascal
GetMem(Puffer, Groesse);
Strom.ReadBuffer(Puffer^, Groesse);
Ergebnis := Pruefsumme(Puffer, Groesse);
```

Richtig:

```pascal
GetMem(Puffer, Groesse);
try
  Strom.ReadBuffer(Puffer^, Groesse);
  Ergebnis := Pruefsumme(Puffer, Groesse);
finally
  FreeMem(Puffer);
end;
```

<a id="stringlist-objects-leak"></a>
### stringlist-objects-leak

**Objekte in einer TStringList ohne Besitz** · Bug · Warnung · Gruppe Fehler finden

AddObject oder InsertObject legt ein neu erzeugtes Objekt (T.Create(…) direkt oder eine so erzeugte lokale Variable, die sonst nur gelesen wird) in eine TStringList (oder THashedStringList), die die Unit ohne OwnsObjects erzeugt, oder in die Items eines Felds vom Typ TListBox, TComboBox, TCheckListBox, TComboBoxEx oder TColorListBox; niemand gibt diese Objekte frei. Besitzend ist eine Liste mit TStringList.Create(True) oder OwnsObjects := True. Still, wenn eine Routine der Unit Liste.Objects[…] liest und etwas freigibt, wenn die Liste weitergegeben wird (ObjekteFreigeben(Liste), anderswo zugewiesen), wenn das Objekt einen Owner hat (Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit Argument) und bei Listen, die nicht in der Unit erzeugt werden. Konfidenz mittel. Schnellkorrektur: TStringList.Create(True) (auch statt Create(False)), bei anderen Konstruktoren OwnsObjects := True nach der Erzeugung; für Items von Steuerelementen keine.

Mit Treffer:

```pascal
FKunden := TStringList.Create;
…
FKunden.AddObject(K.Name, TKunde.Create(K));
```

Richtig:

```pascal
FKunden := TStringList.Create(True);
…
FKunden.AddObject(K.Name, TKunde.Create(K));
```

<a id="message-handler-without-inherited"></a>
### message-handler-without-inherited

**Message-Handler ohne inherited** · Bug · Warnung · Gruppe Fehler finden

Eine Methode mit message WM_… oder CM_… ruft weder inherited noch DefaultHandler (bzw. DefWindowProc, CallWindowProc) auf. Die Standardbehandlung der VCL bzw. von Windows fällt weg: kein Neuausrichten bei WM_SIZE, kein Schließen bei WM_CLOSE, kein Zeichnen bei WM_PAINT. Die Meldung nennt für gängige Nachrichten die Folge. Still bleiben Klassen ohne Vorfahr, Nachrichten aus swallow (Vorgabe WM_ERASEBKGND) und Handler, die Msg.Result selbst setzen (bewusste Antwort wie MA_NOACTIVATE). Sicherheit mittel. Korrektur: inherited; am Anfang einfügen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `swallow` | string-list | `["WM_ERASEBKGND"]` | Nachrichten, die ohne inherited behandelt werden dürfen; ersetzt die Vorgabe. |

Mit Treffer:

```pascal
procedure TfrmHaupt.WMSize(var Msg: TWMSize);
begin
  AnordnungAnpassen;
end;
```

Richtig:

```pascal
procedure TfrmHaupt.WMSize(var Msg: TWMSize);
begin
  inherited;
  AnordnungAnpassen;
end;
```

<a id="string-index-base"></a>
### string-index-base

**String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen** · Bug · Warnung · Gruppe Fehler finden

Die klassischen String-Routinen zählen ab 1: Copy(S, 0, N) und Insert(T, S, 0) wirken nur zufällig wie 1, Delete(S, 0, N) löscht nichts. Der String muss bekannt sein: deklarierter Typ in der Datei, Literal oder .Text/.Caption; dynamische Arrays (ab 0) bleiben still. Pos, PosEx und AnsiPos liefern 0 bei keinem Treffer: Pos(…) > -1, >= 0 und <> -1 sind immer wahr, = -1 und < 0 nie. Umgekehrt übersieht S.IndexOf(…) > 0 bzw. >= 1 den Treffer am Anfang, < 1 bzw. <= 0 zählt ihn als nicht gefunden (Sicherheit mittel; LastIndexOf bleibt still, dort heißt > 0 meist „nicht am Anfang“). Sicherheit hoch für Delete und Pos. Korrektur: Startwert 1 bzw. der richtige Vergleich (> 0, = 0, >= 0, < 0).

Mit Treffer:

```pascal
if Pos(';', Zeile) > -1 then
  Felder := Copy(Zeile, 0, Pos(';', Zeile) - 1);
```

Richtig:

```pascal
if Pos(';', Zeile) > 0 then
  Felder := Copy(Zeile, 1, Pos(';', Zeile) - 1);
```

<a id="delimited-text-without-strict"></a>
### delimited-text-without-strict

**DelimitedText ohne StrictDelimiter** · Bug · Warnung · Gruppe Fehler finden

Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass StrictDelimiter gesetzt wird: DelimitedText trennt dann auch an Leerzeichen, 'Max Muster;Berlin' ergibt drei statt zwei Einträge. Bei Feldern zählt StrictDelimiter in der ganzen Unit (oft im Konstruktor); StrictDelimiter := False ist bewusst und bleibt still, ebenso DelimitedText ohne eigenen Delimiter. Sicherheit hoch. Korrektur: StrictDelimiter := True; vor der Zuweisung einfügen.

Mit Treffer:

```pascal
Teile.Delimiter := ';';
Teile.DelimitedText := Zeile;
```

Richtig:

```pascal
Teile.Delimiter := ';';
Teile.StrictDelimiter := True;
Teile.DelimitedText := Zeile;
```

<a id="self-as-interface-in-constructor"></a>
### self-as-interface-in-constructor

**Self während der Konstruktion als Interface weitergegeben** · Bug · Warnung · Gruppe Fehler finden

Self wird als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann. Gemeldet werden nur zwei echte Fehlerfälle: (1) Eine Klasse mit eigener Referenzzählung (ein _Release in der Klassenkette gibt das Objekt frei, keine Klasse überschreibt NewInstance, die Kette ist bis TObject bekannt) gibt Self im Konstruktor oder in AfterConstruction als Interface weiter: Der Zähler steigt von 0 auf 1 und fällt wieder auf 0, das Objekt wird freigegeben, bevor die Konstruktion endet. (2) Ein Nachfahr von TInterfacedObject gibt Self in AfterConstruction nach inherited als Interface weiter: inherited AfterConstruction hat den Schutzzähler aus NewInstance schon abgebaut. Im Konstruktor eines TInterfacedObject-Nachfahren ist Self geschützt, die Regel bleibt still. Als Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Sicherheit hoch. Korrektur in Fall 2: die Anweisung vor inherited verschieben.

Mit Treffer:

```pascal
procedure TBeobachter.AfterConstruction;
begin
  inherited;
  FQuelle.Anmelden(Self);
end;
```

Richtig:

```pascal
procedure TBeobachter.AfterConstruction;
begin
  FQuelle.Anmelden(Self);
  inherited;
end;
```

<a id="null-compare"></a>
### null-compare

**Vergleich mit Null statt VarIsNull oder IsNull** · Code Smell · Warnung · Gruppe Robustheit und Muster

X = Null bzw. X <> Null vergleicht einen Variant mit Null. Das Ergebnis hängt von der globalen Einstellung System.Variants.NullEqualityRule ab: Mit der Vorgabe ncrLoose vergleicht er wie erwartet, mit ncrStrict ist er nie wahr, mit ncrError löst er eine Exception aus. Eine Bibliothek, ein Testrahmen oder ein anderer Teil des Projekts kann die Einstellung ändern. VarIsNull(X) und Feld.IsNull prüfen unabhängig davon. Gemeldet wird nur, wo der Vergleich für sich steht (Bedingung, Argument, Zuweisung); not X = Null bindet als (not X) = Null und bekommt keine Korrektur. Sicherheit hoch. Korrektur: Feld.IsNull bei X.Value auf FieldByName, FindField, Fields[…], ParamByName, Params[…] oder einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not davor.

Mit Treffer:

```pascal
if qryKunde.FieldByName('Geburtstag').Value = Null then
  Alter := 0;
```

Richtig:

```pascal
if qryKunde.FieldByName('Geburtstag').IsNull then
  Alter := 0;
```

<a id="unchecked-enum-cast"></a>
### unchecked-enum-cast

**Zahl ungeprüft in Aufzählung umgewandelt** · Bug · Hinweis · Gruppe Fehler finden

TStatus(N) mit einem Aufzählungstyp aus der Datei oder dem Index, wenn N aus einem Aufruf der Option sources stammt (FieldByName, ReadInteger, AsInteger, StrToInt): direkt im Argument oder über eine Variable, die zwischen Zuweisung und Umwandlung nicht gelesen (geprüft) wird. Ein Wert außerhalb des Bereichs ergibt einen ungültigen Aufzählungswert, der in case durchfällt. EnsureRange, Min oder Max im Argument gelten als Prüfung; Konstanten, Rechnungen und unbekannte Typen bleiben still. Bei Aufzählungen mit eigenen Ordinalwerten nennt die Meldung den Bereich als Ord(Low(T))..Ord(High(T)). Sicherheit mittel. Korrektur bei direkter Quelle in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise EConvertError davor, System.Math in uses.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `sources` | string-list | `["FieldByName","ReadInteger","AsInteger","StrToInt"]` | Aufrufe, deren Ergebnis als ungeprüft gilt. |

Mit Treffer:

```pascal
Status := TStatus(qry.FieldByName('Status').AsInteger);
```

Richtig:

```pascal
Wert := qry.FieldByName('Status').AsInteger;
if not InRange(Wert, Ord(Low(TStatus)), Ord(High(TStatus))) then
  raise EConvertError.CreateFmt('Ungültiger Wert %d für TStatus', [Wert]);
Status := TStatus(Wert);
```

<a id="createprocess-readonly-commandline"></a>
### createprocess-readonly-commandline

**CreateProcess mit unveränderlicher Befehlszeile** · Bug · Fehler · Gruppe Fehler finden

CreateProcess (CreateProcessW) und CreateProcessAsUser schreiben in den Puffer von lpCommandLine. Ein PChar auf Speicher, der nicht beschreibbar ist, führt zu einer Zugriffsverletzung. Gemeldet wird PChar(…)/PWideChar(…) auf: ein String-Literal oder eine Konstante; eine Verkettung aus genau einem Literal und einem Wert (ist der Wert leer, liefert die RTL das Literal selbst); eine lokale String-Variable, deren letzte Zuweisung vor dem Aufruf eines davon ist, ohne UniqueString danach; einen String-Parameter (Sicherheit mittel, der Aufrufer kann ein Literal übergeben). Funktionsergebnisse wie Format und Verkettungen aus mehreren Teilen sind beschreibbare Heap-Strings und bleiben still, ebenso CreateProcessA, das die Befehlszeile selbst kopiert. Korrektur: Befehlszeile in eine lokale Variable kopieren und UniqueString aufrufen; bei einer Variablen UniqueString vor der Anweisung. In Schleifenbedingungen keine Korrektur.

Mit Treffer:

```pascal
CreateProcess(nil, PChar('notepad.exe ' + Datei), nil, nil, False, 0, nil, nil, SI, PI);
```

Richtig:

```pascal
Befehl := 'notepad.exe ' + Datei;
UniqueString(Befehl);
CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);
```

<a id="form-access-before-create"></a>
### form-access-before-create

**Zugriff auf ein Formular, das noch nicht erzeugt ist** · Bug · Warnung · Gruppe Fehler finden

Der Konstruktor, AfterConstruction oder der OnCreate-Handler eines automatisch erzeugten Formulars bzw. Datenmoduls benutzt die globale Variable eines anderen Formulars, das die .dpr erst danach mit Application.CreateForm erzeugt. Die Variable ist dort noch nil. Die Reihenfolge stammt aus der .dpr des Projekts, zu dem die Unit gehört; der OnCreate-Handler aus der Formulardatei (ohne Eintrag FormCreate bzw. DataModuleCreate). Still, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil), selbst zuweist, mit CreateForm erzeugt oder einen gleichnamigen lokalen Namen deklariert, und bei Formularen, die nicht automatisch erzeugt werden. Jede Variable wird je Routine einmal gemeldet. Sicherheit mittel. Keine Korrektur: die Reihenfolge in der .dpr ändern oder den Zugriff nach OnShow verlegen.

Mit Treffer:

```pascal
procedure TfrmHaupt.FormCreate(Sender: TObject);
begin
  lblNutzer.Caption := dmDaten.Benutzer;
end;
```

Richtig:

```pascal
// .dpr: Application.CreateForm(TdmDaten, dmDaten) before TfrmHaupt
procedure TfrmHaupt.FormCreate(Sender: TObject);
begin
  lblNutzer.Caption := dmDaten.Benutzer;
end;
```

<a id="except-handler-order"></a>
### except-handler-order

**Allgemeiner Exception-Handler vor speziellem** · Bug · Warnung · Gruppe Exceptions

In einem try..except mit mehreren on-Handlern gewinnt der erste passende. Ein Handler für eine Klasse, die ein früherer Handler schon fängt, wird nie erreicht: Sein Code ist tot und die Sonderbehandlung läuft nie. Gemeldet, wenn ein früherer Handler dieselbe Klasse, einen Vorfahren davon, Exception (deckt jede Exception-Klasse ab) oder TObject nennt. Vorfahren kommen aus der Unit, dem Projektindex und einer Tabelle bekannter RTL-, VCL- und FireDAC-Exceptions (etwa EStreamError > EFOpenError, EIntError > ERangeError); unbekannte Klassen werden nur mit Exception und TObject verglichen. Korrektur: den speziellen Handler vor den allgemeinen verschieben (nur, wenn beide Handler auf eigenen Zeilen stehen). Ein doppelter Handler für dieselbe Klasse wird ohne Korrektur gemeldet.

Mit Treffer:

```pascal
except
  on E: Exception do
    Protokoll(E.Message);
  on E: EConvertError do
    ShowMessage('Ungültige Zahl');
end;
```

Richtig:

```pascal
except
  on E: EConvertError do
    ShowMessage('Ungültige Zahl');
  on E: Exception do
    Protokoll(E.Message);
end;
```

<a id="reraise-exception-object"></a>
### reraise-exception-object

**raise E statt raise im Handler** · Code Smell · Warnung · Gruppe Exceptions

raise E; in einem Handler on E: … löst das gefangene Exception-Objekt als neues raise aus. Die RTL gibt das Objekt nicht doppelt frei, aber die Ausnahme beginnt jetzt im Handler: ExceptAddr und die Aufrufliste von Werkzeugen wie madExcept oder JclDebug zeigen auf den Handler statt auf den ursprünglichen Fehler, die Absprungstelle geht verloren. raise; wirft die aktuelle Exception unverändert weiter. Auch raise E at … wird gemeldet, dann ohne Korrektur. Still, wenn der Handler das Objekt mit AcquireExceptionObject übernimmt oder der Variablen ein neues Objekt zuweist, in anonymen Methoden und bei Handlern ohne Variablennamen. Konfidenz hoch. Korrektur: raise E; → raise;.

Mit Treffer:

```pascal
except
  on E: EDatenbank do
  begin
    Protokoll(E.Message);
    raise E;
  end;
end;
```

Richtig:

```pascal
except
  on E: EDatenbank do
  begin
    Protokoll(E.Message);
    raise;
  end;
end;
```

<a id="blocking-call-in-main-thread"></a>
### blocking-call-in-main-thread

**Blockierender Aufruf im Hauptthread** · Code Smell · Warnung · Gruppe Threads

Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects oder Wait in Methoden von Formularen und Frames (Klassen, die von TForm, TCustomForm, TFrame oder TCustomFrame erben) und in Ereignis-Handlern (Methoden mit Parameter Sender) außerhalb von Thread-Klassen. Die Oberfläche friert ein, solange der Aufruf wartet; wartet der andere Thread auf Synchronize, hängt das Programm. WaitFor ohne Timeout auf einer Variablen nennt die Gefahr der Synchronize-Verklemmung. Sleep, WaitForSingleObject und WaitForMultipleObjects zählen nur ohne Empfänger (oder mit Winapi.Windows), WaitFor und Wait nur mit Empfänger. Ein Literal-Timeout unter maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) bleibt still, außer ein kurzes Sleep in einer Warteschleife ohne Application.ProcessMessages. Anonyme Methoden sind ausgenommen (TTask.Run, TThread.Queue), eingebettete Routinen gehören zu ihrer Methode. Konfidenz mittel. Keine Schnellkorrektur: die Arbeit in TTask.Run auslagern und das Ergebnis mit TThread.Queue melden.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `maxSleepMs` | integer | `50` | Literal-Timeouts unter diesem Wert (Millisekunden) werden nicht gemeldet; ein kurzes Sleep in einer Warteschleife schon. |
| `calls` | string-list | `["Sleep","WaitFor","WaitForSingleObject","WaitForMultipleObjects","Wait"]` | Aufrufe, die blockieren. Andere Namen werden unabhängig von ihren Argumenten gemeldet. |

Mit Treffer:

```pascal
procedure TfrmHaupt.btnExportClick(Sender: TObject);
begin
  FExport.Start;
  FExport.WaitFor;
end;
```

Richtig:

```pascal
procedure TfrmHaupt.btnExportClick(Sender: TObject);
begin
  btnExport.Enabled := False;
  TTask.Run(
    procedure
    begin
      FExport.Ausfuehren;
      TThread.Queue(nil, procedure begin btnExport.Enabled := True; end);
    end);
end;
```

<a id="thread-loop-without-terminated"></a>
### thread-loop-without-terminated

**Thread-Schleife ohne Terminated** · Bug · Warnung · Gruppe Threads

Eine while- oder repeat-Schleife in TThread.Execute oder in einer Methode der Thread-Klasse, die nur von dort aufgerufen wird (auch über andere solche Methoden, eingebettete Routinen eingeschlossen), prüft Terminated nicht. Terminate wirkt dann nicht, und WaitFor bzw. Free hängen beim Beenden. Gemeldet für Endlosschleifen (while True, until False) und für Warteschleifen mit Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait oder Yield, deren Bedingung und Rumpf Terminated bzw. CheckTerminated nie erwähnen. Thread-Klassen kommen aus der Unit und dem Index. Begrenzte Schleifen, for-Schleifen, anonyme Methoden und Klassen, die TerminatedSet überschreiben (sie beenden ihre Schleifen auf anderem Weg), bleiben still. Konfidenz hoch. Korrektur: Terminated in die Schleifenbedingung aufnehmen (while True → while not Terminated, sonst and not Terminated; until False → until Terminated, sonst or Terminated).

Mit Treffer:

```pascal
procedure TPoller.Execute;
begin
  while True do
  begin
    Abfragen;
    Sleep(1000);
  end;
end;
```

Richtig:

```pascal
procedure TPoller.Execute;
begin
  while not Terminated do
  begin
    Abfragen;
    Sleep(1000);
  end;
end;
```

<a id="anonymous-thread-not-started"></a>
### anonymous-thread-not-started

**Anonymer Thread nie gestartet** · Bug · Warnung · Gruppe Threads

TThread.CreateAnonymousThread(…) legt den Thread angehalten und mit FreeOnTerminate an. Ohne Start läuft er nie, und weil er nie endet, wird er auch nie freigegeben. Gemeldet für den Aufruf als eigene Anweisung und für eine lokale Variable (auch Inline-Variable), die weder mit Start oder Resume gestartet noch weitergegeben wird (Argument, Zuweisung, Result, Feld). Eigenschaften wie FreeOnTerminate oder OnTerminate zu setzen gilt nicht als Weitergabe. Konfidenz hoch. Korrektur: .Start anhängen; bei einer Variablen T.Start; nach der letzten Anweisung desselben Blocks, die sie erwähnt.

Mit Treffer:

```pascal
TThread.CreateAnonymousThread(
  procedure
  begin
    Synchronisieren;
  end);
```

Richtig:

```pascal
TThread.CreateAnonymousThread(
  procedure
  begin
    Synchronisieren;
  end).Start;
```

<a id="task-exception-unobserved"></a>
### task-exception-unobserved

**Exception in TTask geht verloren** · Code Smell · Hinweis · Gruppe Threads

TTask.Run(…) bzw. TTask.Create(…).Start, dessen Ergebnis nicht gespeichert und nie mit Wait, Status o. ä. abgefragt wird und dessen anonyme Methode kein try … except hat. Eine Exception im Task verschwindet still. Auch gemeldet für eine lokale Variable, die nie wieder vorkommt (bei TTask.Create nur in V.Start). Still bei gespeicherten Ergebnissen (Felder, Result, jede andere Verwendung der Variablen) und bei Methodenzeigern, deren Rumpf die Regel nicht sieht. Konfidenz mittel. Korrektur: den Rumpf in try … except einschließen und die Meldung über TThread.Queue mit ShowMessage im Hauptthread zeigen (ergänzt Vcl.Dialogs, in FireMonkey-Units FMX.Dialogs, und System.SysUtils im uses, wenn sie fehlen); nur, wenn begin und end der anonymen Methode auf eigenen Zeilen stehen.

Mit Treffer:

```pascal
TTask.Run(
  procedure
  begin
    Importieren(Datei);
  end);
```

Richtig:

```pascal
TTask.Run(
  procedure
  begin
    try
      Importieren(Datei);
    except
      on E: Exception do
      begin
        var Fehler := E.Message;
        TThread.Queue(nil,
          procedure
          begin
            ShowMessage(Fehler);
          end);
      end;
    end;
  end);
```

<a id="dataset-loop-without-next"></a>
### dataset-loop-without-next

**Datenmengen-Schleife ohne Next** · Bug · Fehler · Gruppe Datenbank

while not Q.Eof do ohne Q.Next im Rumpf oder mit Next nur auf einem Teil der Wege, die die Schleife fortsetzen (if ohne else, Continue vor Next). Die Schleife dreht endlos auf demselben Datensatz. Delete, MoveBy, Last, Close, FindNext und Free zählen ebenfalls als Weiterbewegen; Break, Exit, Abort und raise beenden die Schleife. Innere while- und for-Schleifen laufen vielleicht nie und zählen nicht. Wird Q im Rumpf weitergegeben (Argument, Zuweisung, with), kann der Aufgerufene den Zeiger bewegen, und die Regel bleibt still. Konfidenz hoch, wenn Next ganz fehlt, mittel, wenn nur einzelne Wege es auslassen. Korrektur: Q.Next; am Ende des begin … end-Rumpfs einfügen (nur, wenn Next ganz fehlt).

Mit Treffer:

```pascal
qryPositionen.First;
while not qryPositionen.Eof do
begin
  Summe := Summe + qryPositionen.FieldByName('Betrag').AsCurrency;
end;
```

Richtig:

```pascal
qryPositionen.First;
while not qryPositionen.Eof do
begin
  Summe := Summe + qryPositionen.FieldByName('Betrag').AsCurrency;
  qryPositionen.Next;
end;
```

<a id="dataset-edit-without-post"></a>
### dataset-edit-without-post

**Edit oder Append ohne Post** · Bug · Warnung · Gruppe Datenbank

Nach Edit, Append oder Insert (ohne Argumente) einer Datenmenge ruft dieselbe Routine weder Post noch Cancel (noch CheckBrowseMode) auf. Die Änderung bleibt offen und geht beim Scrollen still verloren oder wird später unerwartet gespeichert; bei einer Exception dazwischen bricht sie niemand ab. Still, wenn eine andere Routine der Unit dieselbe Datenmenge postet oder abbricht (Bearbeiten-Knopf mit eigenem Speichern-Knopf), und wenn die Datenmenge nach Edit weitergegeben wird (Argument, Zuweisung, with). Konfidenz mittel. Korrektur: die folgenden Anweisungen, die die Datenmenge benutzen, in try … except einschließen, mit Post am Ende des try-Teils und Cancel; raise; im except-Teil.

Mit Treffer:

```pascal
tblKunde.Edit;
tblKunde.FieldByName('Status').AsInteger := Ord(ksAktiv);
Protokollieren;
```

Richtig:

```pascal
tblKunde.Edit;
try
  tblKunde.FieldByName('Status').AsInteger := Ord(ksAktiv);
  tblKunde.Post;
except
  tblKunde.Cancel;
  raise;
end;
Protokollieren;
```

<a id="transaction-without-rollback"></a>
### transaction-without-rollback

**Transaktion ohne Rollback** · Bug · Warnung · Gruppe Datenbank

StartTransaction ohne Rollback im except des unmittelbar folgenden try. Bei einer Exception bleibt die Transaktion offen und hält Sperren. Erkannt für FireDAC (TFDConnection, TFDTransaction), IBX und dbExpress (StartTransaction/Commit/Rollback), dbExpress ab XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, auch als T := Conn.BeginTransaction) und ADO (BeginTrans/CommitTrans/RollbackTrans). Die Option pairs ersetzt diese Paare durch eigene. Das Rollback darf in einem try … except innerhalb eines direkt folgenden try … finally stehen. Still, wenn eine andere Routine der Unit dieselbe Verbindung zurückrollt (Transaktion über mehrere Ereignisse). Konfidenz hoch. Korrektur: die Anweisungen bis zum Commit desselben Blocks in try … except mit Rollback (mit den Argumenten des Commit) und raise; einschließen; nur, wenn im selben Block ein Commit folgt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `pairs` | json | `[{"start":"StartTransaction","commit":"Commit","rollback":"Rollback"},{"start":"BeginTransaction","commit":"CommitFreeAndNil","rollback":"RollbackFreeAndNil"},{"start":"BeginTrans","commit":"CommitTrans","rollback":"RollbackTrans"}]` | Transaktionsmethoden je Bibliothek als [{"start": …, "commit": …, "rollback": …}]; ersetzt die eingebauten Paare. |

Mit Treffer:

```pascal
Verbindung.StartTransaction;
Buchen(Auftrag);
Verbindung.Commit;
```

Richtig:

```pascal
Verbindung.StartTransaction;
try
  Buchen(Auftrag);
  Verbindung.Commit;
except
  Verbindung.Rollback;
  raise;
end;
```

<a id="sql-write-without-where"></a>
### sql-write-without-where

**UPDATE oder DELETE ohne WHERE** · Bug · Warnung · Gruppe Datenbank

UPDATE oder DELETE ohne WHERE in einem String-Literal, in SQL.Text, SQL.Add, CommandText, im ersten Argument von ExecSQL, ExecSQLScalar, Open, ExecuteDirect oder Execute oder in SQL.Strings/CommandText der Formulardatei. Das betrifft alle Zeilen der Tabelle; meist ist die Bedingung vergessen. Die Regel setzt den SQL-Text je Query innerhalb einer Routine zusammen (Clear und ein neuer Text beginnen von vorn) und setzt Konstanten und lokale Werte ein. JOIN, TOP, LIMIT und ROWS schränken die Zeilen ebenfalls ein; ein WHERE in einer Unterabfrage oder einem Kommentar zählt nicht. Unbekannte Teile hinter dem Tabellennamen (Variablen, Aufrufe an der Stelle einer Klausel) lassen die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer Konfidenz. Still, wenn die Routine den SQL-Text weitergibt oder eine andere Routine der Unit ihn ergänzt; SQL der Formulardatei zählt nur, solange die Unit es nicht verändert. Literale außerhalb von SQL-Eigenschaften zählen nur mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte still bleiben. Konfidenz hoch, keine Korrektur; Tabellen, die absichtlich geleert werden, gehören in allowTables.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowTables` | string-list | `[]` | Tabellen, die absichtlich ganz geleert bzw. geändert werden, mit oder ohne Schema. |

Mit Treffer:

```pascal
qry.SQL.Text := 'DELETE FROM Warenkorb';
qry.ExecSQL;
```

Richtig:

```pascal
qry.SQL.Text := 'DELETE FROM Warenkorb WHERE Kunde = :Kunde';
qry.ParamByName('Kunde').AsInteger := KundeId;
qry.ExecSQL;
```

<a id="signature-mismatch"></a>
### signature-mismatch

**Implementierung weicht von der Deklaration ab** · Bug · Fehler · Gruppe Compiler vorab

Der Kopf im implementation-Teil hat andere Parameter (Anzahl, Name, Typ, const/var/out), einen anderen Ergebnistyp, procedure statt function oder eine andere Aufrufkonvention als die Deklaration im Typ (wie E2037). Bei Überladungen wird die nächstliegende Deklaration verglichen (Parameteranzahl, dann Typen, Namen und Modifizierer); ist sie nicht eindeutig, melden declared-not-implemented und implemented-not-declared beide Seiten. Ein Rumpf darf Parameterliste, Ergebnistyp und Aufrufkonvention weglassen. Methoden in {$IF}-Blöcken werden übergangen; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Kopf der Implementierung an die Deklaration angleichen oder als zweite Aktion die Deklaration an die Implementierung (Standardwerte bleiben in der Deklaration). refactoring.syncSignatures = false entfernt nur die Korrekturen.

Entspricht der Compilermeldung `E2037`, `E2211`, `E2065`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
procedure Buchen(const Betrag: Currency; Datum: TDate);
…
procedure TKonto.Buchen(Betrag: Currency; Datum: TDateTime);
```

Richtig:

```pascal
procedure Buchen(const Betrag: Currency; Datum: TDate);
…
procedure TKonto.Buchen(const Betrag: Currency; Datum: TDate);
```

<a id="interface-not-implemented"></a>
### interface-not-implemented

**Interface-Methode fehlt in der Klasse** · Bug · Fehler · Gruppe Compiler vorab

Eine Klasse nennt ein Interface, implementiert aber nicht alle seine Methoden, auch die der Vorfahr-Interfaces (wie E2291). Eine gleichnamige Methode der Klasse mit anderer Signatur wird an dieser Methode gemeldet (wie E2211). Geerbte Methoden der Vorfahrklassen, Methodenzuordnungen (procedure IFoo.Bar = Baz) und Properties mit implements zählen; ebenso die öffentlichen Methoden von TObject und die IInterface-Methoden von TInterfacedObject und ähnlichen RTL-Basen. Endet die Kette der Vorfahrklassen bei einer unbekannten Klasse oder ist das Interface unbekannt, bleibt die Regel still. Gemeldet wird auch eine Methodenzuordnung für ein Interface, das die Klasse nicht nennt (wie E2265). Klassen in {$IF}-Blöcken werden übergangen. Korrektur: fehlende Methoden deklarieren und leer implementieren (nicht bei abweichendem Kopf).

Entspricht der Compilermeldung `E2291`, `E2211`, `E2265`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TDateiLog = class(TInterfacedObject, ILogger)
public
  procedure Info(const Text: string);
end;
```

Richtig:

```pascal
TDateiLog = class(TInterfacedObject, ILogger)
public
  procedure Info(const Text: string);
  procedure Warnung(const Text: string);
  procedure Fehler(const Text: string);
end;
```

<a id="uses-unit-not-found"></a>
### uses-unit-not-found

**Unit in uses nicht gefunden** · Bug · Fehler · Gruppe Compiler vorab

Eine Unit aus uses oder contains liegt weder im Projekt noch in den Ordnern, die der Compiler durchsucht: Ordner der verwendenden Datei, Projektordner, Suchpfade und DCU-Ausgabeordner der .dproj, Bibliothekspfade der Installation, jeweils als .pas oder .dcu und mit jedem Unit-Namespace davor (SysUtils → System.SysUtils); bei Packages zusätzlich die Units der requires-Packages (wie F2613). Ebenso gemeldet: eine Datei aus in '…', die es nicht gibt (F1026), ein Package aus requires, das weder als .dpk noch als .dcp gefunden wird (E2202), eine Unit, die sich selbst einbindet (F2092), und einmal eine fehlende Unit System, also ein fehlender Bibliothekspfad, statt einer Meldung je Unit (F1027). Einträge in {$IF}-Blöcken werden übergangen; ohne bekannte Installation, mit offenem Makro in einem Suchpfad oder einem requires-Package mit unbekanntem Inhalt bleibt die Regel still. Die Meldung nennt ähnliche Units. Korrekturen: die Unit mit Namespace (Forms → Vcl.Forms) bzw. eine ähnlich geschriebene einsetzen oder den Ordner unter dem Projekt, in dem die Unit liegt, in DCC_UnitSearchPath der Basiskonfiguration der .dproj aufnehmen.

Entspricht der Compilermeldung `F2613`, `F1027`, `F1026`, `E2202`, `F2092`.

Stufe B (Namensauflösung über Units).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `searchPaths` | string | `"project"` | Wo Units gesucht werden: project (wie der Compiler: Projekt, Suchpfade der .dproj, Bibliothekspfade, .pas und .dcu), atlas (was Atlas kennt: Index und Quellpfade der Installation) oder both. |

Mit Treffer:

```pascal
uses
  System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnungs.Druck;
```

Richtig:

```pascal
uses
  System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnung.Druck;
```

<a id="unresolved-attribute"></a>
### unresolved-attribute

**Attribut nicht gefunden und still ignoriert** · Bug · Fehler · Gruppe Compiler vorab

Ein Attribut [Name] lässt sich weder einer Klasse NameAttribute noch Name zuordnen, meist weil eine Unit in uses fehlt. Delphi warnt nur (W1074) und übergeht das Attribut: DUnitX-Tests laufen dann nicht, JSON- oder ORM-Zuordnungen fehlen. Die Meldung nennt die Unit, die das Attribut im Index deklariert; eine Fassaden-Unit, die den Typ aus einer anderen Kandidatin weiterreicht (DUnitX.TestFramework statt DUnitX.Attributes), geht vor, und die DUnitX-Attribute sind auch ohne DUnitX im Index bekannt. Attribute des Compilers wie Weak, Unsafe, Ref und Volatile zählen immer. Still ohne die Unit System im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das Attribut deklarieren), in {$IF}-Blöcken und bei unbekanntem Vorfahren der umgebenden Klasse; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Unit in uses aufnehmen.

Entspricht der Compilermeldung `W1074`, `E2289`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
uses
  System.SysUtils;
type
  [TestFixture]
  TKundeTests = class
```

Richtig:

```pascal
uses
  System.SysUtils, DUnitX.TestFramework;
type
  [TestFixture]
  TKundeTests = class
```

<a id="comparison-as-statement"></a>
### comparison-as-statement

**Vergleich statt Zuweisung als Anweisung** · Bug · Fehler · Gruppe Compiler vorab

Ein Vergleich wie Result = 0; oder FAktiv = True; steht als eigene Anweisung; gemeint war :=. Delphi meldet E2014 erst beim Übersetzen. Bei = mit zuweisbarer linker Seite (Variable, Feld, Element, Ziel eines Zeigers) ersetzt die Korrektur = durch :=. Andere Vergleiche und Ausdrücke, deren Wert verfällt (A <> B;, A + B;, not A;, ein Literal), meldet die Regel ohne Korrektur, ebenso einen Aufruf links.

Entspricht der Compilermeldung `E2014`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
Result = 0;
```

Richtig:

```pascal
Result := 0;
```

<a id="duplicate-case-label"></a>
### duplicate-case-label

**Doppelte case-Marke** · Bug · Fehler · Gruppe Compiler vorab

Zwei Marken einer case-Anweisung decken denselben Wert ab (wie E2030), auch über Bereiche (1..5 und 3), Konstanten mit gleichem Wert, Zeichen ('a' und #97) und Bereiche von Aufzählungswerten. Gleiches gilt für die Marken eines varianten Record-Teils (wie E2027). Die Werte ergeben sich aus Zahlen, Zeichen, Konstanten und Aufzählungswerten über die Namensauflösung; Marken mit unbekanntem Wert vergleicht die Regel nur über den Text. Gemeldet wird eine Marke nur, wenn die frühere immer mit übersetzt wird: verschiedene Zweige desselben {$IF} stoßen nie zusammen. Korrektur: den doppelten Wert aus dem späteren Zweig entfernen bzw. den ganzen Zweig, wenn es seine einzige Marke war; eine teilweise Überschneidung von Bereichen meldet die Regel ohne Korrektur.

Entspricht der Compilermeldung `E2030`, `E2027`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
case Status of
  stNeu, stOffen: Bearbeiten;
  stGeschlossen: Archivieren;
  stOffen: Erinnern;
end;
```

Richtig:

```pascal
case Status of
  stNeu, stOffen: Bearbeiten;
  stGeschlossen: Archivieren;
end;
```

<a id="field-after-method"></a>
### field-after-method

**Feld nach Methoden im selben Abschnitt** · Bug · Fehler · Gruppe Compiler vorab

In einem Sichtbarkeitsabschnitt einer Klasse, eines Objekts oder Records folgt eine Felddeklaration auf eine Methode oder Property. Delphi verlangt Felder zuerst oder einen neuen Abschnitt bzw. var (E2169); FPC übersetzt das. Korrekturen: das Feld samt Attributen und Kommentaren an den Anfang des Abschnitts verschieben oder var davor setzen. In Records steht var vorn, weil das Verschieben das Speicherlayout ändert. Gemeldet wird ein Feld nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird; mit bedingten Zweigen dazwischen gibt es nur var.

Entspricht der Compilermeldung `E2169`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
TKunde = class
private
  function GetName: string;
  FName: string;
end;
```

Richtig:

```pascal
TKunde = class
private
  FName: string;
  function GetName: string;
end;
```

<a id="overload-directive-missing"></a>
### overload-directive-missing

**Überladung ohne overload oder mit gleicher Signatur** · Bug · Fehler · Gruppe Compiler vorab

Zwei Routinen oder Methoden gleichen Namens im selben Gültigkeitsbereich (ein Typ, die Unit über interface und implementation, die in einer Routine verschachtelten Routinen), von denen mindestens eine kein overload trägt (wie E2254, bzw. E2267, wenn es der früheren fehlt), oder zwei Überladungen mit gleichen Parameterarten und -typen (wie E2252, bzw. E2301 mit auch gleichem Ergebnistyp). Ein Rumpf zu einer früheren Deklaration (interface, forward) zählt nicht. Operatoren, Methodenrümpfe und Deklarationen in verschiedenen Zweigen desselben {$IF} bleiben außen vor. Korrektur: overload; an alle Deklarationen ohne anhängen, vor den übrigen Direktiven.

Entspricht der Compilermeldung `E2254`, `E2267`, `E2252`, `E2301`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
procedure Laden(const Datei: string);
procedure Laden(Strom: TStream);
```

Richtig:

```pascal
procedure Laden(const Datei: string); overload;
procedure Laden(Strom: TStream); overload;
```

<a id="duplicate-declaration"></a>
### duplicate-declaration

**Bezeichner doppelt deklariert** · Bug · Fehler · Gruppe Compiler vorab

Ein Bezeichner ist im selben Gültigkeitsbereich zweimal deklariert (wie E2004): lokale Variable, Konstante, Typ oder Label und ein Parameter der Routine, zwei Felder, ein Feld und eine Methode oder Property eines Typs, zwei Typen, Konstante und Variable der Unit über interface und implementation hinweg. Ebenso eine Unit doppelt in uses oder in den uses-Klauseln von interface und implementation zugleich (Option checkUses). Überladungen und Rümpfe von Routinen, eine Vorwärtsdeklaration und ihr Typ, TList neben TList<T> und Deklarationen in verschiedenen Zweigen desselben {$IF} zählen nicht. Korrektur: zweite Deklaration entfernen (den ganzen var-, const-, type- oder label-Abschnitt, wenn sie seine einzige war; bei uses den doppelten Eintrag); keine bei Parametern, Methoden und Properties.

Entspricht der Compilermeldung `E2004`.

Stufe A (Parser genügt).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `checkUses` | boolean | `true` | Doppelte Einträge in uses-Klauseln melden. |

Mit Treffer:

```pascal
procedure TRechnung.Summieren(Betrag: Currency);
var
  Betrag: Currency;
begin
```

Richtig:

```pascal
procedure TRechnung.Summieren(Betrag: Currency);
begin
```

<a id="conditional-directive-unbalanced"></a>
### conditional-directive-unbalanced

**Bedingte Direktiven unvollständig oder unbekannt** · Bug · Fehler · Gruppe Compiler vorab

Ein {$IFDEF}, {$IFNDEF}, {$IFOPT} oder {$IF}, das nie geschlossen wird, sodass der Rest der Datei an seiner Bedingung hängt (wie E2095, bei {$IF} E2280); {$ELSE}, {$ELSEIF}, {$ENDIF} oder {$IFEND} ohne passendes {$IF…} oder nach {$ELSE} (wie E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} oder {$UNDEF} ohne gültiges Symbol (wie E2173); eine unbekannte Direktive oder ein unbekannter {$WARN}-Bezeichner (wie W1030), mit dem nächstliegenden bekannten Namen als Korrektur; {$POPOPT} ohne {$PUSHOPT} (wie W1078) oder {$PUSHOPT} ohne {$POPOPT} (wie W1079); ein ungültiger Wert für {$ALIGN} bzw. {$A} (wie E2573). Unbekannte Namen prüft die Regel nicht in Zweigen, deren Bedingung FPC abfragt, {$PUSHOPT}/{$POPOPT} nur, wenn keines davon in einem bedingten Zweig steht. Korrekturen: {$ENDIF} vor der ersten Leerzeile hinter dem offenen Block ergänzen, überzählige Direktive entfernen, Tippfehler korrigieren.

Entspricht der Compilermeldung `E2095`, `E2280`, `E2279`, `E2173`, `W1030`, `W1078`, `W1079`, `E2573`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
{$IFDEF DEBUG}
  Protokoll.Ausfuehrlich := True;

procedure TDienst.Starten;
```

Richtig:

```pascal
{$IFDEF DEBUG}
  Protokoll.Ausfuehrlich := True;
{$ENDIF}

procedure TDienst.Starten;
```

<a id="override-target-missing"></a>
### override-target-missing

**override ohne passende virtuelle Methode** · Bug · Fehler · Gruppe Compiler vorab

Eine Methode mit override, zu der kein Vorfahr eine virtuelle (oder dynamic, abstract) Methode mit gleichem Namen und gleichen Parametern hat (wie E2137): oft ein Tippfehler (Destory) oder im Vorfahren geänderte Parameter. Die Meldung nennt die nächstliegende virtuelle Methode des Vorfahren („dort heißt es Ausfuehren(const Modus: TModus)“) bzw. einen ähnlichen Namen. Außerdem: override auf eine statische Methode (wie E2170), auf eine finale (wie E2352) und Ableiten von einer sealed-Klasse (wie E2353). Vorfahren sucht die Regel in der Datei und im Symbolindex; bricht die Kette an einer unbekannten Klasse ab, bleibt sie still. Ohne System im Index gelten die virtuellen Methoden von TObject als vorhanden. Typparameter generischer Vorfahren, Typaliase und Synonyme wie Longint passen. Korrektur: Signatur des Vorfahren in Deklaration und Implementierung übernehmen.

Entspricht der Compilermeldung `E2137`, `E2170`, `E2352`, `E2353`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TDienst = class
protected
  procedure Ausfuehren(const Modus: TModus); virtual;
end;
TImportDienst = class(TDienst)
protected
  procedure Ausfuehren(Modus: Integer); override;
end;
```

Richtig:

```pascal
TImportDienst = class(TDienst)
protected
  procedure Ausfuehren(const Modus: TModus); override;
end;
```

<a id="abstract-class-instantiated"></a>
### abstract-class-instantiated

**Instanz einer Klasse mit abstrakten Methoden** · Bug · Warnung · Gruppe Compiler vorab

Create auf einer Klasse, die abstrakte Methoden deklariert oder erbt, ohne sie zu überschreiben (wie W1020), oder auf einer als abstract deklarierten Klasse (wie E2402). Der Aufruf einer abstrakten Methode löst zur Laufzeit EAbstractError aus; die Meldung nennt die offenen Methoden. Klassen sucht die Regel in der Datei und im Symbolindex; Überladungen mit gleicher Parameterzahl gelten als eine Methode. Aufrufe über Klassenreferenzen, inherited Create und Konstruktor-Rümpfe prüft sie nicht. Korrektur für eine Klasse dieser Datei, die die abstrakten Methoden erbt: dort überschreiben (wie die Code-Aktion „überschreiben“).

Entspricht der Compilermeldung `W1020`, `E2402`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
Form := TForm.Create;
Gesamt := Gesamt + Form.Flaeche;
```

Richtig:

```pascal
Form := TKreis.Create;
Gesamt := Gesamt + Form.Flaeche;
```

<a id="property-accessor-invalid"></a>
### property-accessor-invalid

**Getter oder Setter einer Property ungültig** · Bug · Fehler · Gruppe Compiler vorab

Der Name hinter read oder write einer Property passt nicht: Er ist weder in der Klasse noch in ihren Vorfahren deklariert oder ist eine Property (wie E2168); Getter oder Setter haben die falsche Art, Parameter oder Typen (wie E2234); der Setter nimmt einen var- oder out-Parameter (wie E2282); die Zugriffsmethode ist überladen (wie E2271); eine Klassen-Property nutzt ein Instanzmitglied oder eine Klassenmethode ohne static (wie E2355), eine Instanz-Property ein Klassenmitglied (wie E2356); eine Array-Property oder eine Property mit index nutzt ein Feld (wie E2174); ein Feldselektor geht über ein Feld, das kein Record ist (wie E2459), nennt ein Mitglied, das kein Feld ist (wie E2461), oder ein Feld, das dem Record fehlt (wie E2562). Namen sucht die Regel in der Datei und für Vorfahren im Symbolindex; sie bleibt still, wenn die Kette der Vorfahren abbricht, der Name nur in einem inaktiven Zweig steht, die Klasse ihn nicht sieht oder Include-Dateien einbindet. Typen vergleicht sie nur, wenn beide eingebaut oder als eigener Typ deklariert sind. Korrektur für ein fehlendes F<Name>, Get<Name> oder Set<Name>: anlegen (wie die Vervollständigung hinter read/write, completion.accessorSection).

Entspricht der Compilermeldung `E2168`, `E2234`, `E2282`, `E2271`, `E2355`, `E2356`, `E2174`, `E2459`, `E2461`, `E2562`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TKunde = class
private
  FName: string;
public
  property Name: string read FName write SetName;
end;
```

Richtig:

```pascal
TKunde = class
private
  FName: string;
  procedure SetName(const Value: string);
public
  property Name: string read FName write SetName;
end;
```

<a id="assign-to-property-member"></a>
### assign-to-property-member

**Zuweisung an ein Feld eines Property-Records** · Bug · Fehler · Gruppe Compiler vorab

Zuweisung an ein Feld eines Records, den eine Property mit Getter, eine Default- oder Array-Property oder ein Funktionsergebnis nur als Kopie liefert (wie E2064): Die Zuweisung hat keine Wirkung. Zuweisungen an untypisierte Konstanten meldet die Regel ebenso. Typen kommen aus der Namensauflösung; gemeldet wird nur bei sicher bekanntem Record-Typ. Liest die Property direkt ein Feld, schreibt Delphi in dieses Feld, und die Regel bleibt still. Korrektur bei einer Property mit write: über eine lokale Variable zuweisen und zurückschreiben; die Variable wird in der Routine deklariert, die Unit ihres Typs in uses ergänzt.

Entspricht der Compilermeldung `E2064`, `E2453`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
Rahmen.BoundsRect.Left := 0;
```

Richtig:

```pascal
R := Rahmen.BoundsRect;
R.Left := 0;
Rahmen.BoundsRect := R;
```

<a id="readonly-property-assigned"></a>
### readonly-property-assigned

**Zuweisung an eine Property ohne write** · Bug · Fehler · Gruppe Compiler vorab

Zuweisung an eine Property ohne write (wie E2129) bzw. Lesen einer Property ohne read (wie E2130). Die Regel meldet nur, wenn die Namensauflösung die Property sicher findet; Neudeklarationen ohne read und write (property Caption;) gelten als unbekannt. Korrekturen: Count := 0 wird Clear, wenn der Typ Clear hat; in einer Methode der deklarierenden Klasse das Feld hinter read zuweisen; für eine Property dieser Datei den Setter anlegen und write ergänzen.

Entspricht der Compilermeldung `E2129`, `E2130`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
Liste.Count := 0;
```

Richtig:

```pascal
Liste.Clear;
```

<a id="sql-select-star"></a>
### sql-select-star

**SELECT * im Code** · Code Smell · Hinweis · Gruppe Datenbank

SELECT * oder SELECT Alias.* in einer Spaltenliste, an denselben Stellen wie bei sql-write-without-where: String-Literale, SQL.Text, SQL.Add, CommandText, das erste Argument von ExecSQL, Open und ähnlichen Aufrufen, Konstanten, lokale Werte und SQL.Strings/CommandText der Formulardatei. Neue Spalten ändern still die Datenmenge, persistente Felder passen nicht mehr, und es werden mehr Daten übertragen als nötig. Unterabfragen zählen; EXISTS (SELECT * …) und COUNT(*) bleiben still, ebenso eine Spaltenliste aus einer Variablen. Literale außerhalb von SQL-Eigenschaften zählen nur mit SELECT in Großbuchstaben und einem FROM, damit Meldungstexte still bleiben. Standardmäßig aus (in den Regeleinstellungen oder mit dem Profil strict einschalten). Konfidenz hoch. Schnellkorrektur: Steht der Stern in einem einzelnen Literal und hat die Datenmenge persistente Felder in der Formulardatei, ersetzt sie * durch deren FieldName-Liste (ohne berechnete und Nachschlagefelder).

Mit Treffer:

```pascal
qry.SQL.Text := 'SELECT * FROM Kunden WHERE Ort = :Ort';
```

Richtig:

```pascal
qry.SQL.Text := 'SELECT Id, Name, Ort FROM Kunden WHERE Ort = :Ort';
```

<a id="path-concat-without-delimiter"></a>
### path-concat-without-delimiter

**Pfad ohne Trennzeichen zusammengesetzt** · Bug · Warnung · Gruppe Robustheit und Muster

Ein Ordner ohne abschließendes Trennzeichen wird mit + an einen Datei- oder Ordnernamen gehängt: Ergebnisse von ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHomePath, TPath.GetDocumentsPath und den übrigen TPath.Get…Path-Ordnern, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory und TDirectory.GetParent, direkt aufgerufen oder in einer lokalen Variablen, der die Routine nur solche Werte zuweist. Das Ergebnis ist C:\Datendatei.txt statt C:\Daten\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter und TPath.GetTempPath enden mit einem Trennzeichen und bleiben still, ebenso Trennzeichen, Endungen (ExtractFileExt, '.bak') und Texte, die mit Leerzeichen oder Satzzeichen beginnen. Ein Literal als Name meldet mit hoher, ein Bezeichner mit mittlerer Konfidenz. Geht eine lokale Variable an eine Prozedur außer ForceDirectories, FileExists und ähnlichen lesenden Aufrufen, kann sie dort geändert werden und bleibt still. Schnellkorrektur: TPath.Combine(Ordner, Name), System.IOUtils wird in die uses eingetragen.

Mit Treffer:

```pascal
Ordner := TPath.GetDocumentsPath;
Datei := Ordner + 'export.csv';
```

Richtig:

```pascal
Ordner := TPath.GetDocumentsPath;
Datei := TPath.Combine(Ordner, 'export.csv');
```

<a id="hardcoded-path"></a>
### hardcoded-path

**Fester Dateipfad im Code** · Code Smell · Hinweis · Gruppe Robustheit und Muster

Ein String-Literal mit Laufwerksbuchstaben (C:\…, auch mit /) oder UNC-Pfad (\\server\freigabe\…); Pfade unter C:\Users bzw. C:\Documents and Settings bekommen eine eigene Meldung. Auf anderen Rechnern fehlt der Pfad. Laufwerkswurzeln wie 'C:\' allein und die Präfixe \\?\ und \\.\ bleiben still, ebenso Kommentare, Test-Units und Units aus allowUnits (z. B. eine Unit mit den Standardpfaden einer Installation). Konfidenz hoch, keine Korrektur: den Pfad aus TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), den Einstellungen oder einer Umgebungsvariablen holen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowUnits` | string-list | `[]` | Units, in denen feste Pfade erlaubt sind, nach Unit-Namen; * am Ende passt auf ein Präfix (App.Config*). |

Mit Treffer:

```pascal
Protokoll.SaveToFile('C:\Users\marco\Desktop\log.txt');
```

Richtig:

```pascal
Protokoll.SaveToFile(TPath.Combine(TPath.GetDocumentsPath, 'log.txt'));
```

<a id="filename-compare-case"></a>
### filename-compare-case

**Dateinamen mit = verglichen** · Bug · Hinweis · Gruppe Robustheit und Muster

Ein Vergleich mit = oder <>, bei dem eine Seite ein Datei- oder Pfadname ist: das Ergebnis von ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt, ExpandFileName, ChangeFileExt und verwandten Funktionen aus System.SysUtils, von TPath.GetFileName, GetExtension, GetDirectoryName, GetFullPath, Combine und verwandten Methoden oder eine Variable bzw. Eigenschaft, deren Name auf FileName endet, oder Application.ExeName. Unter Windows sind Kunde.pas und kunde.PAS dieselbe Datei. Vergleiche mit Leertext, nil oder einem Literal ohne Buchstaben bleiben still, ebenso ExtractFileDir(X) = X (beide Seiten stammen aus demselben Text). Konfidenz mittel. Korrektur: SameFileName(A, B), bei <> not SameFileName(A, B); ergänzt System.SysUtils in der uses-Klausel, falls nötig.

Mit Treffer:

```pascal
if ExtractFileName(Datei) = 'Config.ini' then
```

Richtig:

```pascal
if SameFileName(ExtractFileName(Datei), 'Config.ini') then
```

<a id="initialization-not-finalized"></a>
### initialization-not-finalized

**Beim Start erzeugtes Objekt wird nicht freigegeben** · Bug · Warnung · Gruppe Robustheit und Muster

Ein Objekt wird in initialization mit TKlasse.Create erzeugt und einer Unit-Variablen zugewiesen oder in einem class constructor erzeugt und einer class var zugewiesen, aber die Unit gibt es nirgends frei (kein Free, Destroy, DisposeOf, Release oder FreeAndNil in der ganzen Unit). FastMM meldet beim Beenden ein Leck; in Packages bleibt das Objekt bei jedem Entladen liegen. Interface- und Record-Typen, Komponenten mit Owner (Application, Self, Owner) und Objekte, die die Unit weitergibt, bleiben still: Jede Erwähnung der Variablen muss harmlos sein (Zugriff auf ein Mitglied, Vergleich mit nil, Assigned, erneutes Create oder Zuweisung von nil); als Argument übergeben, anderswo zugewiesen, with, eine Property, die sie liest, oder FreeOnTerminate lassen die Regel schweigen. Bei Variablen aus dem interface-Abschnitt und öffentlichen class vars schweigt sie auch, wenn eine andere Unit im Index den Namen verwendet. Konfidenz hoch. Korrektur: FreeAndNil am Ende von finalization bzw. im class destructor; fehlt der finalization-Abschnitt oder der class destructor (Deklaration und Rumpf), wird er angelegt, System.SysUtils kommt bei Bedarf in die uses-Klausel.

Mit Treffer:

```pascal
initialization
  GProtokoll := TProtokoll.Create;
end.
```

Richtig:

```pascal
initialization
  GProtokoll := TProtokoll.Create;

finalization
  FreeAndNil(GProtokoll);
end.
```

<a id="compiler-warnings-disabled"></a>
### compiler-warnings-disabled

**Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet** · Code Smell · Warnung · Gruppe Robustheit und Muster

{$WARNINGS OFF}, {$HINTS OFF}, {$WARN X OFF}, {$R-}, {$Q-} (auch zusammen als {$R-,Q-}) oder die langen Formen {$RANGECHECKS OFF} und {$OVERFLOWCHECKS OFF} ohne spätere Wiederherstellung bis zum Ende der Unit. Meldungen und Prüfungen verschwinden weit über die gemeinte Stelle hinaus, die 0/0/0-Regel wird unterlaufen. Jedes spätere ON, +, DEFAULT oder ERROR für denselben Schalter zählt als Wiederherstellung, auch in Mustern mit {$IFOPT}/{$IFDEF}, ebenso ein späteres {$POPOPT}. Ein Schalter, dessen Gegenstück in einem anderen Zweig desselben {$IF} steht ({$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}), ist eine gewollte Einstellung je Konfiguration und bleibt still, ebenso eine Direktive ohne Code dahinter; {$R *.dfm} ist eine Ressource, keine Bereichsprüfung. Die Option allow nennt Schalter, die aus bleiben dürfen (Warnungsnamen wie SYMBOL_PLATFORM, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS). Konfidenz hoch. Korrektur: die Wiederherstellung ({$WARNINGS ON}, {$WARN X DEFAULT}, {$R+} …) hinter dem nächsten Block einfügen; bei Bereichs- und Überlaufprüfung nur einzeln, weil {$R+} eine Prüfung einschalten kann, die das Projekt aus hat.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allow` | string-list | `[]` | Schalter, die bis zum Ende der Unit aus bleiben dürfen: Warnungsnamen für {$WARN} (SYMBOL_PLATFORM), WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS; ohne Groß-/Kleinschreibung. |

Mit Treffer:

```pascal
{$WARNINGS OFF}
function AlteBerechnung(const Wert: Integer): Integer;
begin
  Result := Wert * 2;
end;
```

Richtig:

```pascal
{$WARNINGS OFF}
function AlteBerechnung(const Wert: Integer): Integer;
begin
  Result := Wert * 2;
end;
{$WARNINGS ON}
```

<a id="dll-export-unsafe"></a>
### dll-export-unsafe

**Exportierte Routine nicht sicher über DLL-Grenzen aufrufbar** · Bug · Warnung · Gruppe Robustheit und Muster

Eine in exports aufgeführte Routine dieser Datei hat keine Aufrufkonvention (stdcall, cdecl, safecall, winapi oder pascal; register ist die Delphi-Konvention) oder erwartet bzw. liefert einen String (string, UnicodeString, AnsiString, UTF8String, RawByteString), ein dynamisches Array (TBytes, TArray<T>, …DynArray, array of T aus der Datei), ein Objekt oder ein Interface ohne GUID. Aufrufer aus anderen Sprachen oder Delphi-Versionen stürzen ab; Strings und dynamische Arrays liegen im Speichermanager der DLL. WideString, ShortString, PChar, offene Array-Parameter und Records sind in Ordnung. Objekte erkennt die Regel nur sicher: Klassen der Datei, des Index und häufige RTL-Klassen; Interfaces nur aus der Datei. Routinen aus anderen Units und Überladungen, die der exports-Eintrag nicht festlegt, bleiben still. Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays erlaubt (Option allowShareMem). Die Meldung steht am Eintrag in exports; bei Strings empfiehlt sie PChar mit Puffer und Länge. Konfidenz hoch. Korrektur: stdcall in jedem Kopf der Routine ergänzen (nur einzeln, weil das die Schnittstelle für vorhandene Aufrufer ändert).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowShareMem` | boolean | `true` | Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays in exportierten Routinen erlaubt. |

Mit Treffer:

```pascal
function KundeName(Id: Integer): string;
…
exports
  KundeName;
```

Richtig:

```pascal
function KundeName(Id: Integer; Puffer: PChar; Laenge: Integer): Integer; stdcall;
…
exports
  KundeName;
```

<a id="destructor-not-nil-safe"></a>
### destructor-not-nil-safe

**Destruktor benutzt Felder, die nil sein können** · Bug · Warnung · Gruppe Fehler finden

Wirft ein Konstruktor, ruft Delphi sofort den Destruktor auf, obwohl noch nicht alle Felder angelegt sind. Gemeldet wird ein Zugriff im Destruktor (oder in einer privaten Methode, die nur der Destruktor aufruft) auf ein Feld wie FZeilen.Clear, FDatei.Position oder FZeilen[0], wenn ein Konstruktor der Klasse das Feld (TKlasse.Create) erst nach einem Aufruf anlegt, der werfen kann, oder nur auf manchen Wegen. Die Zugriffsverletzung verdeckt dann die eigentliche Exception. Free, FreeAndNil, DisposeOf und Zugriffe nach Assigned(FFeld) bzw. FFeld <> nil sind nil-sicher; BeforeDestruction läuft auf diesem Weg nicht. Konstruktoren von RTL-Klassen, die höchstens EOutOfMemory werfen (TStringList.Create, TObjectList<T>.Create(True)), inherited Create und Supports zählen nicht als werfend. Konfidenz hoch. Schnellkorrektur: if Assigned(FFeld) then vor die Anweisung setzen. Mit onlyAfterRaisingCode aus zählt jedes im Konstruktor angelegte Feld.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `onlyAfterRaisingCode` | boolean | `true` | Nur melden, wenn der Konstruktor vor dem Anlegen des Felds etwas aufruft, das eine Exception werfen kann. |

Mit Treffer:

```pascal
constructor TImport.Create(const Datei: string);
begin
  inherited Create;
  FStrom := TFileStream.Create(Datei, fmOpenRead);
  FZeilen := TStringList.Create;
end;

destructor TImport.Destroy;
begin
  FZeilen.Clear;
  FZeilen.Free;
  FStrom.Free;
  inherited;
end;
```

Richtig:

```pascal
destructor TImport.Destroy;
begin
  if Assigned(FZeilen) then
    FZeilen.Clear;
  FZeilen.Free;
  FStrom.Free;
  inherited;
end;
```

<a id="handle-leak"></a>
### handle-leak

**Windows-Handle wird nicht geschlossen** · Bug · Warnung · Gruppe Fehler finden

Ein Windows-Handle in einer lokalen Variablen wird auf einem Weg zum Ende der Routine nicht mit dem passenden Gegenstück geschlossen: CreateFile, CreateEvent, CreateMutex, OpenProcess, CreateProcess (hProcess, hThread) und CreateToolhelp32Snapshot mit CloseHandle, FindFirstFile mit FindClose, RegOpenKeyEx/RegCreateKeyEx mit RegCloseKey, LoadLibrary mit FreeLibrary, GetDC mit ReleaseDC, CreatePen/CreateBrush/CreateFont/CreateBitmap mit DeleteObject, CreateCompatibleDC mit DeleteDC und weitere. Zurückgeben, Speichern in einem Feld oder einer globalen Variablen, Übergabe an eine unbekannte Routine und Verwenden in einer anonymen Methode gelten als Weitergabe. Zweige, in denen eine if-Prüfung sagt, dass das Öffnen misslang (H = 0, H = INVALID_HANDLE_VALUE, RegOpenKeyEx(...) <> ERROR_SUCCESS), und Ausnahmewege (siehe pair-without-finally) zählen nicht. Die Option pairs ergänzt eigene Paare. Konfidenz mittel. Schnellkorrektur, wenn das Handle nie geschlossen wird: die Anweisungen nach dem Öffnen in try … finally mit dem Schließen einschließen bzw. das Schließen anhängen, wenn das Öffnen die letzte Anweisung ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `pairs` | json | `[]` | Zusätzliche Paare aus Öffnen und Schließen als "Oeffnen>Schliessen" oder {"open": …, "close": …}; die Öffnen-Funktion liefert das Handle, die Schließen-Prozedur bekommt es als einziges Argument. |

Mit Treffer:

```pascal
H := CreateFile(PChar(Datei), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
if H = INVALID_HANDLE_VALUE then
  RaiseLastOSError;
ReadFile(H, Puffer, SizeOf(Puffer), Gelesen, nil);
```

Richtig:

```pascal
H := CreateFile(PChar(Datei), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
if H = INVALID_HANDLE_VALUE then
  RaiseLastOSError;
try
  ReadFile(H, Puffer, SizeOf(Puffer), Gelesen, nil);
finally
  CloseHandle(H);
end;
```

<a id="global-formatsettings-modified"></a>
### global-formatsettings-modified

**Globale FormatSettings wird verändert** · Bug · Warnung · Gruppe Robustheit und Muster

Zuweisung an die globale FormatSettings oder eines ihrer Felder (auch an die veralteten globalen Variablen DecimalSeparator, ShortDateFormat, ThousandSeparator … älterer Delphi-Versionen). Das ändert die Formatierung für die ganze Anwendung, für alle Packages im selben Prozess (im IDE-Plugin die IDE selbst) und für alle Threads und ist nicht threadsicher; häufig eine Notlösung, um einen Punkt als Dezimaltrenner zu erzwingen. Gemeldet wird nur, wenn der Name sicher die Variable aus System.SysUtils ist: keine lokale Deklaration, kein Mitglied der Klasse oder ihrer Vorfahren (still, wenn die Kette der Vorfahren an einer unbekannten Klasse endet), nicht in with. Ergänzt format-without-settings, das Formatierungsaufrufe ohne Settings meldet. Konfidenz hoch. Schnellkorrektur, wenn die Routine die globalen Settings nur einmal ändert und danach etwas formatiert: lokale TFormatSettings anlegen (TFormatSettings.Invariant bei DecimalSeparator := '.', sonst eine Kopie von FormatSettings mit dem geänderten Feld) und an die folgenden Formatierungsaufrufe übergeben. Mit allowInProgram sind die Zuweisungen in der .dpr erlaubt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowInProgram` | boolean | `false` | Zuweisungen in der .dpr erlauben, etwa einmal beim Programmstart. |

Mit Treffer:

```pascal
procedure TExport.Schreiben;
begin
  FormatSettings.DecimalSeparator := '.';
  Zeile := FloatToStr(Betrag);
end;
```

Richtig:

```pascal
procedure TExport.Schreiben;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;
  Zeile := FloatToStr(Betrag, FS);
end;
```

<a id="component-interface-dangling"></a>
### component-interface-dangling

**Komponente als Interface gespeichert und freigegeben** · Bug · Warnung · Gruppe Fehler finden

Ein Nachfahr von TComponent (Formular, Frame, Datenmodul, eigene Komponente) implementiert ein Interface, aber TComponent zählt keine Referenzen. Gemeldet wird das Speichern des Objekts als Interface in einem Feld, einer globalen Variablen oder einer Liste (FAnsicht as IBeobachter an Bus.Anmelden, FListe.Add, Register, Subscribe …, Zuweisung an ein Feld oder eine globale Variable, Add in TList<IFoo>/TInterfaceList), wenn dieselbe Unit das Objekt freigibt (Free, Release, DisposeOf, FreeAndNil) und es nirgends abmeldet: FreeNotification auf dem Objekt, ein anderer Aufruf am selben Empfänger mit dem Objekt als Argument (Abmelden, Remove, Unsubscribe …), Clear oder eine weitere Zuweisung an dasselbe Feld. Nach der Freigabe zeigt das gespeicherte Interface ins Leere. Still bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren an einer unbekannten Klasse endet. Ebenso gemeldet, ohne Schnellkorrektur: Nachfahren von TInterfacedObject, die so gespeichert und zusätzlich mit Free freigegeben werden; das gespeicherte Interface hält dann ein freigegebenes Objekt, und eine Abmeldung davor gäbe es schon frei. Konfidenz mittel. Schnellkorrektur: Abmeldung vor der ersten Freigabe einfügen (Empfänger.Abmelden(…), wenn der Typ des Empfängers das Gegenstück hat, bzw. Feld := nil).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `componentClasses` | string-list | `["TComponent"]` | Basisklassen ohne Referenzzählung; mit TComponent zählen auch die bekannten VCL- und FMX-Klassen (TForm, TFrame, TDataModule …). |

Mit Treffer:

```pascal
procedure TfrmHaupt.AnsichtOeffnen;
begin
  FAnsicht := TfrmKunden.Create(Self);
  Bus.Anmelden(FAnsicht as IBeobachter);
end;

procedure TfrmHaupt.AnsichtSchliessen;
begin
  FAnsicht.Free;
end;
```

Richtig:

```pascal
procedure TfrmHaupt.AnsichtOeffnen;
begin
  FAnsicht := TfrmKunden.Create(Self);
  Bus.Anmelden(FAnsicht as IBeobachter);
end;

procedure TfrmHaupt.AnsichtSchliessen;
begin
  Bus.Abmelden(FAnsicht as IBeobachter);
  FAnsicht.Free;
end;
```

<a id="unit-name-mismatch"></a>
### unit-name-mismatch

**Unit-Name passt nicht zum Dateinamen** · Bug · Fehler · Gruppe Compiler vorab

Der Name hinter unit weicht vom Dateinamen ab, meist nach dem Umbenennen der Datei außerhalb der IDE (wie E1038, W1038). Groß-/Kleinschreibung zählt nicht, Punkte im Namen schon. In Programmen, Bibliotheken und Packages wird außerdem ein Eintrag uses X in 'Datei.pas' gemeldet, dessen Datei eine andere Unit deklariert (wie E2085); die Regel liest dazu die Datei. Programme, Bibliotheken und Packages selbst vergleicht sie nicht mit dem Dateinamen, weil der Compiler das auch nicht tut. {$WARN UNIT_NAME_MISMATCH OFF} oder {$WARNINGS OFF} vor dem Unit-Namen schaltet die Regel wie den Compiler ab. Korrekturen: Unit-Namen an den Dateinamen anpassen (die Datei umbenennen bleibt Sache der IDE) bzw. den uses-Eintrag auf die Unit der Datei ändern.

Entspricht der Compilermeldung `E1038`, `W1038`, `E2085`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
// File: Kunden.Daten.pas
unit Kunden.Model;

interface
```

Richtig:

```pascal
// File: Kunden.Daten.pas
unit Kunden.Daten;

interface
```

<a id="text-after-final-end"></a>
### text-after-final-end

**Text nach dem abschließenden end.** · Code Smell · Warnung · Gruppe Compiler vorab

Nach dem abschließenden end. einer Unit, eines Programms, einer Bibliothek oder eines Packages steht noch Quelltext. Der Compiler ignoriert ihn (wie W1011); meist ist es Code, der beim Einfügen ans Dateiende geraten ist und nie übersetzt wird. Kommentare und Direktiven werden nicht gemeldet (Option allowComments). Die Regel sucht das abschließende end. hinter dem letzten Abschnitt des Syntaxbaums und schweigt, solange der Parser Fehler meldet oder end. in einem {$IF…}-Zweig steht; {$WARNINGS OFF} vor end. schaltet sie ab. Schnellkorrektur: Text nach end. entfernen.

Entspricht der Compilermeldung `W1011`.

Stufe A (Parser genügt).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowComments` | boolean | `true` | Kommentare und Direktiven nach end. erlauben. |

Mit Treffer:

```pascal
end.

procedure TKunde.Speichern;
begin
```

Richtig:

```pascal
end.
```

<a id="exports-invalid"></a>
### exports-invalid

**exports-Klausel unzulässig** · Bug · Fehler · Gruppe Compiler vorab

Eine exports-Klausel in einer Routine (wie E2191), der Export einer threadvar oder einer mit local deklarierten Routine (wie E2276), einer Variablen, Konstanten oder eines Typs (wie E2121) oder derselbe Eintrag bzw. Exportname zweimal (wie E2287). Namen löst die Regel nur gegen globale Deklarationen der Datei auf; Namen aus anderen Units und Namen mit Punkt bleiben still, ebenso zwei Einträge in sich ausschließenden {$IF…}-Zweigen. Überladene Routinen mit verschiedenen Parameterlisten oder Exportnamen gelten als verschiedene Einträge. Ergänzt dll-export-unsafe (#973). Schnellkorrektur: doppelten Eintrag entfernen.

Entspricht der Compilermeldung `E2191`, `E2276`, `E2121`, `E2287`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
exports
  Initialisieren,
  Berechnen,
  Initialisieren;
```

Richtig:

```pascal
exports
  Initialisieren,
  Berechnen;
```

<a id="unit-name-conflict"></a>
### unit-name-conflict

**Unit-Name kollidiert** · Bug · Fehler · Gruppe Compiler vorab

Eine Unit heißt wie eine für den Compiler reservierte Unit, System oder SysInit (wie E2272), oder {$NOINCLUDE X} nennt eine Unit, die der Compiler nicht kennt (wie E2242); dafür braucht die Regel die Unit-Suche des Projekts und schweigt ohne sichere Antwort. Die Quellen der RTL (source/rtl) prüft sie nicht. Nicht gemeldet: E2447, W1051 und X2421 gehören zu den Namensräumen der .NET-Metadaten, die dcc32/dcc64 nicht erzeugt; für E2399 nennt die Dokumentation keine Bedingung, und eine Unit Kunden neben Kunden.Daten übersetzt Delphi ohne Fehler (Spring.pas neben Spring.Collections.pas). Schnellkorrektur für {$NOINCLUDE}: eine ähnlich geschriebene bekannte Unit einsetzen.

Entspricht der Compilermeldung `E2272`, `E2242`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
unit System;

interface
```

Richtig:

```pascal
unit Kunden.Systemdienste;

interface
```

<a id="implicit-variants-unit"></a>
### implicit-variants-unit

**Variant ohne System.Variants in uses** · Code Smell · Hinweis · Gruppe Compiler vorab

Die Unit verwendet Variant oder OleVariant als Typ, ohne System.Variants in uses zu haben. Der Compiler bindet die Unit dann still ein (wie W1040) und ändert damit die Initialisierungsreihenfolge. Die Regel zählt Typangaben im Syntaxbaum (Variablen, Felder, Parameter, Ergebnisse, Typargumente); Variants in uses gilt auch in einem {$IF…}-Zweig und ohne Namespace. Still in System, SysInit und Variants selbst, wenn die Datei einen eigenen Typ Variant deklariert, und nach {$WARN IMPLICIT_VARIANTS OFF}. Standardmäßig aus (Profil strict). Schnellkorrektur: System.Variants in uses aufnehmen (Variants, wenn die Unit SysUtils oder Classes ohne Namespace nennt).

Entspricht der Compilermeldung `W1040`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
uses
  System.SysUtils;
…
var Wert: Variant;
```

Richtig:

```pascal
uses
  System.SysUtils, System.Variants;
…
var Wert: Variant;
```

<a id="file-encoding-unsupported"></a>
### file-encoding-unsupported

**Kodierung oder Zeichen, die der Compiler nicht liest** · Bug · Fehler · Gruppe Compiler vorab

Die Datei ist UTF-32 kodiert (wie F2438; erkannt an der BOM, dann keine weiteren Meldungen), oder der Code außerhalb von Strings, Kommentaren und Direktiven enthält ein Zeichen, das der Compiler ablehnt (wie E2038): typografische Anführungszeichen aus einer Webseite oder Textverarbeitung, die ASCII-Zeichen ! " ? \ ` | ~ sowie Satz- und Sonderzeichen und Emoji jenseits von ASCII. Buchstaben, Ziffern und Verbinder wie U+203F bleiben in Bezeichnern erlaubt; asm-Blöcke und {$IF…}-Zweige werden übersprungen; Steuer-, Format- und Leerzeichen melden control-char und invisible-char. Schnellkorrektur: ein Paar Anführungszeichen auf einer Zeile wird zum String; ein einzelnes Zeichen mit eindeutigem ASCII-Gegenstück (– − × ÷ ≤ ≥ ≠, Vollbreiten-ASCII) wird ersetzt. Eine UTF-32-Datei hat keine Schnellkorrektur; als UTF-8 mit BOM speichern.

Entspricht der Compilermeldung `F2438`, `E2038`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
Titel := ‚Bericht‘;
```

Richtig:

```pascal
Titel := 'Bericht';
```

<a id="anonymous-capture-invalid"></a>
### anonymous-capture-invalid

**Anonyme Methode erfasst, was sie nicht erfassen darf** · Bug · Fehler · Gruppe Compiler vorab

Eine anonyme Methode greift auf einen var-, out- oder untypisierten Parameter oder auf Result einer umgebenden Routine bzw. anonymen Funktion zu (wie E2555). Der Name wird von innen nach außen aufgelöst (Parameter, var/const/type, lokale Routinen, Inline-Variablen, for var); in with und asm bleibt die Regel still, Deklarationen in Zweigen bedingter Übersetzung, die die Stelle ausschließen, zählen nicht. Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren, in der anonymen Methode nur diese verwenden und nach der Anweisung zurückschreiben, wenn die Methode sie zuweist.

Entspricht der Compilermeldung `E2555`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
procedure Load(var Count: Integer);
begin
  TTask.Run(procedure begin Inc(Count); end);
end;
```

Richtig:

```pascal
procedure Load(var Count: Integer);
var
  CountCopy: Integer;
begin
  CountCopy := Count;
  TTask.Run(procedure begin Inc(CountCopy); end);
  Count := CountCopy;
end;
```

<a id="operator-declaration-invalid"></a>
### operator-declaration-invalid

**Operator falsch deklariert** · Bug · Fehler · Gruppe Compiler vorab

Ein class operator in einem Record oder einer Klasse ist so deklariert, wie Delphi es ablehnt: unbekannter Operatorname (wie E2393), falsche Parameterzahl (E2517), eigener Typ fehlt in den Parametern (E2518) bzw. bei Implicit/Explicit in Parametern und Ergebnis (E2521), Inc/Dec mit anderem Ergebnistyp als dem ersten Parameter (E2519), Vergleichsoperator ohne Boolean-Ergebnis (E2520), Umwandlung in oder aus einem Vorfahren (E2522, Kette innerhalb der Datei) oder Assign ohne var vor dem ersten Parameter (E2464). Typen gelten als gleich, wenn ihre Namen ohne Unit-Präfix und Typargumente übereinstimmen; Aliase des eigenen Typs in der Datei halten die Regel still, True, False und OnesComplement gelten als bekannt. Korrekturen: nächstliegender Operatorname, Boolean als Ergebnis, Ergebnis wie der erste Parameter, var vor dem ersten Parameter, Parameterliste nach Vorlage; jeweils in Deklaration und Rumpf.

Entspricht der Compilermeldung `E2393`, `E2464`, `E2517`, `E2518`, `E2519`, `E2520`, `E2521`, `E2522`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
TGeld = record
  class operator Equal(const A, B: TGeld): Integer;
end;
```

Richtig:

```pascal
TGeld = record
  class operator Equal(const A, B: TGeld): Boolean;
end;
```

<a id="generic-declaration-invalid"></a>
### generic-declaration-invalid

**Generische Deklaration unzulässig** · Bug · Fehler · Gruppe Compiler vorab

Eine generische Deklaration, die Delphi ablehnt: Einschränkungen class und record zugleich (wie E2507), eine Einschränkung doppelt (E2603), record zusammen mit constructor (E2516), eine Klasse neben class bzw. record (E2552), zwei Klassen (E2553), ein Einschränkungstyp, der weder Klasse noch Interface ist (E2510); Typparameter an Aufzählung, Menge, Teilbereich, Zeiger, Klassenreferenz, Alias oder Helfer (E2508), an Destruktor oder Klassenkonstruktor (E2528), Operator (E2529), globaler Routine (E2530), virtueller, dynamischer, message- oder override-Methode (E2533) oder Interface-Methode (E2535); class of eines parametrisierten Typs (E2548), generische Klasse, die von TCustomAttribute erbt (E2549), parametrisierter Typ als Attribut (E2565); ein Typparameter, der einen des umgebenden Typs verdeckt (H2509); ein Aufruf mit einer Zahl Typargumente, die keine Überladung hat (E2551, Klassen und Records der Datei mit Vorfahren aus der Datei); eine Methode eines generischen Typs oder eine generische Methode aus dem interface-Teil, die ein Symbol des implementation-Teils verwendet (E2506; still in with und wenn die Vorfahrenkette nicht bekannt ist). Typen zählen nur, wenn sie eingebaut oder in der Datei deklariert sind; unbekannte Typen halten die Regel still. Lokale Prozeduren in generischen Methoden (E2570) meldet die Regel erst, wenn der Abgleich mit Delphi 12/13 bestätigt, dass sie noch abgelehnt werden.

Entspricht der Compilermeldung `E2506`, `E2507`, `E2508`, `E2510`, `E2516`, `E2528`, `E2529`, `E2530`, `E2533`, `E2535`, `E2548`, `E2549`, `E2551`, `E2552`, `E2553`, `E2565`, `E2603`, `H2509`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
procedure Swap<T>(var A, B: T);
```

Richtig:

```pascal
type
  TSwap = record
    class procedure Swap<T>(var A, B: T); static;
  end;
```

<a id="type-restriction-violated"></a>
### type-restriction-violated

**Sprachregel für Records, Inline und Helfer verletzt** · Bug · Fehler · Gruppe Compiler vorab

Feste Sprachregeln, die erst der Compiler meldet: virtuelle Methoden (wie E2379) oder andere virtuelle Direktiven (override, abstract, reintroduce, message, final; E2463) in Records, parameterlose Konstruktoren (E2394), Konstruktoren, deren Parameter alle Vorgabewerte haben (E2471), und Destruktoren (E2465) in Records, Klassenmethoden in Records ohne static (E2398); in Record-Helfern virtuelle Methoden (E2598) und die übrigen virtuellen Direktiven (E2475); Felder in Helfern (class var ist erlaubt, E2599), Destruktor (E2295) oder Klassenkonstruktor (E2358) in einem Class-Helfer, ein Helfer-Konstruktor, dessen erster Befehl kein Aufruf ohne Argumente ist (E2296), ein Class-Helfer mit Vorfahr-Helfer für einen Typ, der nicht vom Typ des Vorfahren abstammt (E2294, nur bei bekannter Vorfahrenkette), ein Helfer als Typ einer Deklaration (E2527) oder in einem generischen Typ (E2589); mehrere Klassenkonstruktoren (E2359, sich ausschließende bedingte Zweige zählen einmal), Klassenkonstruktoren mit Parametern (E2360) oder virtual, dynamic bzw. message (E2534); Methoden, Properties, Klassenmitglieder, Typen und Konstanten in lokalen oder anonymen Records (E2433 bis E2437); inline an virtuellen oder dynamischen Methoden (E2425), an Konstruktoren und Destruktoren (E2442), mit offenen Array-Parametern (E2439), mit asm-Rumpf (E2426), im interface-Teil deklariert mit Symbolen des implementation-Teils (E2441), als lokale Routine mit Zugriff auf Variablen der umgebenden Routine (E2449) oder mit Aufruf eigener lokaler Routinen (E2501); lokale, absolute oder initialisierte threadvar (E2189, E2190, E2194). Die Prüfungen gelten für alle unterstützten Delphi-Versionen (10 Seattle bis 13). Option disabledChecks nimmt einzelne Codes aus. Korrekturen: Direktive entfernen, static ergänzen.

Entspricht der Compilermeldung `E2189`, `E2190`, `E2194`, `E2294`, `E2295`, `E2296`, `E2358`, `E2359`, `E2360`, `E2379`, `E2394`, `E2398`, `E2425`, `E2426`, `E2433`, `E2434`, `E2435`, `E2436`, `E2437`, `E2439`, `E2441`, `E2442`, `E2449`, `E2463`, `E2465`, `E2471`, `E2475`, `E2501`, `E2527`, `E2534`, `E2589`, `E2598`, `E2599`.

Stufe A (Parser genügt).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `disabledChecks` | string-list | `[]` | Compilercodes, die die Regel nicht prüft, z. B. ["E2425"]. |

Mit Treffer:

```pascal
TPoint2 = record
  X, Y: Integer;
  function Length: Double; virtual;
end;
```

Richtig:

```pascal
TPoint2 = record
  X, Y: Integer;
  function Length: Double;
end;
```

<a id="attribute-usage-invalid"></a>
### attribute-usage-invalid

**Attribut falsch verwendet** · Bug · Fehler · Gruppe Compiler vorab

Ein Attribut des Compilers steht dort, wo Delphi es ablehnt: [Weak] an einem Feld oder einer Variablen, deren Typ sicher weder Klasse noch Interface ist (eingebaute Werttypen, Records, Aufzählungen, Mengen, Arrays, Zeigertypen der Datei, Aliase verfolgt; wie E2584), [Volatile] an Typ, Routine, Methode oder Property (E2325), Weak, Unsafe, Volatile oder Ref doppelt an derselben Deklaration (E2326; sich ausschließende Zweige zählen nicht) oder ein Attributargument, das sicher eine Variable oder Routine der Datei ist (E2448; vor dem Attribut sichtbar, nicht durch eine gleichnamige Konstante, einen Typ oder eine andere Deklaration verdeckt). Eigene Attribute dürfen mehrfach stehen; ein Typ Weak bzw. WeakAttribute in der Datei macht die Regel für diesen Namen still. Keine Schnellkorrektur.

Entspricht der Compilermeldung `E2325`, `E2326`, `E2448`, `E2584`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TCounter = class
private
  [Weak] FCount: Integer;
end;
```

Richtig:

```pascal
TCounter = class
private
  [Weak] FOwner: IInterface;
  FCount: Integer;
end;
```

<a id="typeinfo-invalid"></a>
### typeinfo-invalid

**TypeInfo oder Default mit unzulässigem Argument** · Bug · Fehler · Gruppe Compiler vorab

TypeInfo oder Default bekommt eine Variable statt eines Typs (wie E2133, E2537: Parameter, lokale, Inline- und Unit-Variablen, Felder, Properties, Result, for- und Ausnahmevariablen), TypeInfo einen Typ ohne RTTI (Aufzählung mit festen Werten, Dateityp, Text/TextFile; E2134) oder Default einen Dateityp (E2538). Namen werden von innen nach außen aufgelöst; in with, in Helfern, in Methoden von Typen außerhalb der Datei, bei Deklarationen in anderen bedingten Zweigen und wenn Datei oder Index ein eigenes TypeInfo bzw. Default deklarieren, bleibt die Regel still. Korrektur: den deklarierten Typ der Variablen einsetzen.

Entspricht der Compilermeldung `E2133`, `E2134`, `E2537`, `E2538`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
Name := GetEnumName(TypeInfo(Status), Ord(Status));
```

Richtig:

```pascal
Name := GetEnumName(TypeInfo(TStatus), Ord(Status));
```

<a id="missing-begin-end"></a>
### missing-begin-end

**Bedingung oder Schleife ohne begin … end** · Code Smell · Hinweis · Gruppe Stil und Metriken

Der Rumpf von if … then, else, for, while oder with ist eine einzelne Anweisung ohne begin … end. Mit der Regel haben Bedingungen und Schleifen immer einen Block; eine später ergänzte zweite Anweisung landet so nicht versehentlich außerhalb. else if bleibt erlaubt (das innere if braucht keinen eigenen Block); repeat … until, case … end, try … end und asm … end sind schon Blöcke. Eine leere Anweisung (if X then ;) meldet empty-statement. Rümpfe mit {$IFDEF} meldet die Regel nicht. Solange die Regel an ist, meldet redundant-begin-end nichts. Schnellkorrekturen: begin … end um die Anweisung setzen, für die ganze Methode oder für die ganze Datei, eingerückt nach den Formatierungseinstellungen; ein ; vor else wandert in den Block (kein E2153); mit format.elsePlacement "sameLine" steht else hinter dem neuen end (end else).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `statements` | string-list | `["if","else","for","while","with"]` | Geprüfte Anweisungen; case für die Zweige von case-Anweisungen ergänzen. |
| `allowSingleLineExit` | boolean | `false` | Exit, Continue, Break und raise in derselben Zeile wie die Bedingung erlauben (if … then Exit;). |
| `allowSameLine` | boolean | `false` | Eine einzelne Anweisung in derselben Zeile wie Bedingung bzw. Schleifenkopf erlauben. |

Mit Treffer:

```pascal
if Kunde.Gesperrt then
  Protokoll.Warnung('Gesperrt')
else
  Speichern(Kunde);
```

Richtig:

```pascal
if Kunde.Gesperrt then
begin
  Protokoll.Warnung('Gesperrt');
end
else
begin
  Speichern(Kunde);
end;
```

<a id="inherited-constructor-after-try"></a>
### inherited-constructor-after-try

**Geerbter Konstruktor erst im try-Block** · Bug · Hinweis · Gruppe Compiler vorab

Ein Konstruktor betritt einen try-Block, bevor er den geerbten Konstruktor aufgerufen hat (wie H2505). Self ist dort noch nicht initialisiert; eine Exception im Block kann auf halb erzeugte Felder treffen. Als geerbter Konstruktor gilt inherited ohne Namen, mit dem Namen des Konstruktors oder mit einem Namen, der mit Create beginnt. Zweige von {$IFDEF} werden getrennt geprüft. Korrektur, wenn der Aufruf die erste Anweisung im try-Block ist: vor try ziehen.

Entspricht der Compilermeldung `H2505`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
constructor TDienst.Create;
begin
  try
    inherited Create;
    FListe := TList<TAuftrag>.Create;
```

Richtig:

```pascal
constructor TDienst.Create;
begin
  inherited Create;
  try
    FListe := TList<TAuftrag>.Create;
```

<a id="variant-record-managed-field"></a>
### variant-record-managed-field

**Verwalteter Typ im varianten Teil eines Records** · Bug · Fehler · Gruppe Compiler vorab

Im varianten Teil eines Records (case … of) steht ein String, ein dynamisches Array, ein Interface, ein Variant oder ein Record mit solchen Feldern (wie E2154), ein verwalteter Record mit class operator Initialize oder Finalize (wie E2418) oder ein Typparameter ohne record-Einschränkung (wie E2569); ebenso hinter file of (wie E2155, E2417). Typen werden in der Datei und im Index aufgelöst; unbekannte bleiben still. Korrekturen: Feld vor case in den festen Teil verschieben, ShortString verwenden oder den Typparameter mit record einschränken.

Entspricht der Compilermeldung `E2154`, `E2155`, `E2418`, `E2417`, `E2569`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TWert = record
  case Art: TArt of
    waZahl: (Zahl: Double);
    waText: (Text: string);
end;
```

Richtig:

```pascal
TWert = record
  Text: string;
  case Art: TArt of
    waZahl: (Zahl: Double);
end;
```

<a id="guid-syntax-invalid"></a>
### guid-syntax-invalid

**GUID mit falscher Schreibweise** · Bug · Fehler · Gruppe Compiler vorab

Die GUID eines Interfaces oder einer typisierten TGUID-Konstante hat nicht die Form '{8-4-4-4-12}' (wie E2204): fehlende Klammern, falsche Zahl oder Länge der Blöcke, Zeichen, die keine Hexadezimalziffern sind, oft nach Hand-Bearbeitung. Geprüft werden nur einzelne Literale; Verkettungen und Konstanten bleiben still. Korrekturen: neue GUID erzeugen; fehlen nur die Klammern, sie ergänzen. Ergänzt interface-guid und duplicate-interface-guid.

Entspricht der Compilermeldung `E2204`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
ILogger = interface
  ['{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6}']
```

Richtig:

```pascal
ILogger = interface
  ['{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C}']
```

<a id="untyped-pointer-refcount"></a>
### untyped-pointer-refcount

**Untypisierter Zeiger umgeht die Referenzzählung** · Bug · Warnung · Gruppe Compiler vorab

Ein Interface wird über eine Typumwandlung nach Pointer zugewiesen (Pointer(FIntf) := P, wie W1070). Die Referenzzählung läuft dann nicht mit: das Objekt wird zu früh freigegeben oder nie. Die Regel meldet nur, wenn die Namensauflösung den Interface-Typ sicher kennt; Strings (string, AnsiString …) meldet sie ebenfalls, mit dem Zusatz „dcc meldet das nicht“, weil Delphi bei ihnen nur unter NEXTGEN warnt. Felder mit [weak] oder [unsafe] bleiben still. Korrekturen für ein Interface-Feld dieser Datei mit Pointer(Y) oder nil rechts: das Feld mit [weak] bzw. [unsafe] auszeichnen und ohne Pointer zuweisen.

Entspricht der Compilermeldung `W1070`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
Pointer(FBesitzer) := Pointer(Besitzer);
```

Richtig:

```pascal
[weak] FBesitzer: IBesitzer;
…
FBesitzer := Besitzer;
```

<a id="type-too-large"></a>
### type-too-large

**Typ überschreitet eine Größengrenze** · Bug · Fehler · Gruppe Compiler vorab

Ein statisches Array oder Record ist 2 GB groß oder größer (wie E2100), ebenso eine Instanz eines generischen Typs dieser Datei (wie E2543). Atlas rechnet eine untere Grenze aus den Deklarationen: Indexbereiche über konstante Ausdrücke, Konstanten und Aufzählungen der Datei, eingebaute Typen, Records aus dem Index; Unbekanntes zählt 0, gemeldet wird also nur sicher. Gemeldet wird nur der innerste Typ, der die Grenze überschreitet. E2419 (Records über 1 MB) gilt nur für Delphi für .NET und wird nicht gemeldet. Keine Korrektur; stattdessen ein dynamisches Array oder einen Zeiger verwenden.

Entspricht der Compilermeldung `E2100`, `E2543`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
type TPuffer = array[0..High(Integer)] of Int64;
```

Richtig:

```pascal
type TPuffer = array of Int64;
```

<a id="comparison-always-constant"></a>
### comparison-always-constant

**Vergleich immer wahr oder immer falsch** · Bug · Warnung · Gruppe Compiler vorab

Vergleich einer Variablen, eines Feldes, einer Property oder eines Funktionsergebnisses vom eingebauten Ganzzahltyp mit einer Konstanten außerhalb bzw. am Rand des Wertebereichs (wie W1021, W1022): Cardinal >= 0 ist immer wahr, Byte > 255 immer falsch. Ebenso case-Marken außerhalb des Bereichs des case-Ausdrucks (wie W1018). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit dem Vergleich übersetzt wird. NativeInt, LongInt und ihre vorzeichenlosen Gegenstücke gelten mit dem weitesten Bereich aller Plattformen; Teilbereichstypen meldet die Regel nicht. Length(…) < 0 und Length(…) >= 0 meldet sie ebenfalls, obwohl dcc dort nicht warnt; die Meldung sagt das dazu.

Entspricht der Compilermeldung `W1021`, `W1022`, `W1018`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
while Rest >= 0 do  // Rest: Cardinal
```

Richtig:

```pascal
while Rest > 0 do
```

<a id="constant-initializer-mismatch"></a>
### constant-initializer-mismatch

**Initialisierung einer Konstanten passt nicht** · Bug · Fehler · Gruppe Compiler vorab

Eine typisierte Konstante oder initialisierte Variable vom statischen Array-Typ hat mehr oder weniger Elemente als ihr Indexbereich (wie E2072), typisch nach einem neuen Wert in einer Aufzählung (array[TStatus] of string); geprüft je Dimension und auch für benannte Array-Typen der Datei. Ebenso Record-Konstanten, deren Felder in anderer Reihenfolge als deklariert stehen (wie E2083). Indexbereiche: Teilbereiche mit konstanten Grenzen, Aufzählungen ohne eigene Werte, Boolean, Byte, Char usw. Deklarationen mit bedingten Direktiven gelten als unsicher. Korrekturen: fehlende Einträge mit Platzhalter ergänzen (Name des Aufzählungswerts als Kommentar), Felder in die Reihenfolge der Deklaration bringen.

Entspricht der Compilermeldung `E2072`, `E2083`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
StatusText: array[TStatus] of string = ('Neu', 'Offen', 'Geschlossen');  // TStatus has 4 values
```

Richtig:

```pascal
StatusText: array[TStatus] of string = ('Neu', 'Offen', 'Geschlossen', ''{stArchiviert});
```

<a id="case-selector-not-ordinal"></a>
### case-selector-not-ordinal

**case oder for ohne ordinalen Typ** · Bug · Fehler · Gruppe Compiler vorab

case über einen nicht ordinalen Ausdruck (wie E2001): Strings, Gleitkommazahlen, Klassen und Interfaces; for-Schleife mit nicht ordinaler Zählvariable (wie E2032); case-Marken und Array-Grenzen, die Variablen, Felder, Properties, Parameter oder typisierte Konstanten statt Konstanten sind (wie E2026). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der Anweisung übersetzt wird. Korrektur bei Strings mit lauter String-Literalen als Marken: case IndexStr(S, […]) of mit den Positionen als Marken, System.StrUtils kommt in die uses.

Entspricht der Compilermeldung `E2001`, `E2032`, `E2026`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
case Befehl of 'start': Starten; 'stop': Stoppen; end;  // Befehl: string
```

Richtig:

```pascal
case IndexStr(Befehl, ['start', 'stop']) of 0: Starten; 1: Stoppen; end;
```

<a id="suspicious-string-pointer-cast"></a>
### suspicious-string-pointer-cast

**Zeiger und Zeichenbreite eines Strings passen nicht zusammen** · Bug · Warnung · Gruppe Compiler vorab

PChar bzw. PWideChar auf einen AnsiString, RawByteString oder UTF8String und PAnsiChar auf einen string, UnicodeString oder WideString (wie W1044): Zeiger und Zeichenbreite passen nicht zusammen, typisch nach der Unicode-Umstellung; die API liest dann Datenmüll bzw. nur das erste Zeichen. Gemeldet wird nur bei sicher bekanntem Typ des Arguments, dessen Deklaration immer mit der Umwandlung übersetzt wird. string(PAnsiChar) wandelt korrekt um, ein Zeiger auf TBytes kann gewollt sein; beides meldet die Regel nicht. Korrekturen: eigene Variable mit passendem Stringtyp deklarieren (PChar(Pfad) mit Pfad: AnsiString wird Pfad: string), string(…) bzw. AnsiString(…) um das Argument, passenden Zeigertyp verwenden.

Entspricht der Compilermeldung `W1044`, `W1048`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
var Pfad: AnsiString; ... DeleteFile(PChar(Pfad));
```

Richtig:

```pascal
var Pfad: string; ... DeleteFile(PChar(Pfad));
```

<a id="inaccessible-member"></a>
### inaccessible-member

**Zugriff auf ein nicht sichtbares Mitglied** · Bug · Fehler · Gruppe Compiler vorab

Zugriff A.B auf ein Mitglied, das an der Stelle nicht sichtbar ist: private bzw. strict private einer anderen Unit oder Klasse (wie E2361), protected bzw. strict protected außerhalb der deklarierenden Unit und ihrer Nachfahren (wie E2362, E2389). In einer Klassenmethode oder statischen Methode sind Instanzfelder, -methoden und -Properties der Klasse nicht erreichbar (wie E2124). Eine Property, die auf ein private-Mitglied eines Vorfahren derselben Unit verweist, meldet die Regel als Warnung (wie W1045). Gemeldet wird nur, wenn die Namensauflösung den Empfänger und seinen Typ sicher kennt und das Mitglied erst ohne Rücksicht auf die Sichtbarkeit findet; protected-Mitglieder bleiben über eine Klasse der eigenen Unit sichtbar (TZugang(Control).Click). Deklarationen in bedingten Zweigen, Methoden von Helfern und verschachtelten Typen bleiben still.

Entspricht der Compilermeldung `E2361`, `E2362`, `E2389`, `E2124`, `W1045`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
class function TKonfig.Standard: TKonfig;
begin
  Result := TKonfig.Create;
  Result.Pfad := FBasisPfad;
end;
```

Richtig:

```pascal
class function TKonfig.Standard: TKonfig;
begin
  Result := TKonfig.Create;
  Result.Pfad := Result.FBasisPfad;
end;
```

<a id="unused-private-member"></a>
### unused-private-member

**Privates Mitglied wird nie verwendet** · Code Smell · Hinweis · Gruppe Compiler vorab

Ein private- oder strict-private-Feld, eine Methode, Konstante oder Property kommt in der Unit nirgends vor (wie H2219, das der Compiler nur für Methoden meldet; Felder ebenso, außer includeFields ist aus). Jedes Vorkommen des Namens als Bezeichner zählt als Verwendung, auch in inaktiven bedingten Zweigen und hinter read/write; Deklarationen und Methodenköpfe zählen nicht. Ausgenommen: Methoden mit message, virtual, dynamic, override oder abstract, Methoden von Typen, die Interfaces umsetzen, Konstruktoren und Destruktoren, Mitglieder mit Attributen (RTTI), Namen aus der Formulardatei und Units mit Include-Dateien. Korrektur: Deklaration (samt ///-Doku) und den Rumpf einer Methode entfernen; nicht, wenn sich mehrere Mitglieder die Deklaration teilen oder die Methode überladen ist.

Entspricht der Compilermeldung `H2219`.

Stufe A (Parser genügt).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `includeFields` | boolean | `true` | Auch nie verwendete private Felder melden (der Compiler meldet nur Methoden). |

Mit Treffer:

```pascal
  TImport = class
  private
    FAltFormat: Boolean;
    procedure KonvertiereAlt;
  end;
```

Richtig:

```pascal
  TImport = class
  private
  end;
```

<a id="unused-public-member"></a>
### unused-public-member

**Öffentliches Mitglied wird im Projekt nie verwendet** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine public- oder published-Methode, -Konstante oder -Property (wahlweise auch protected-Mitglieder, Felder und Klassenvariablen sowie Routinen und Konstanten im interface-Abschnitt einer Unit) wird in den Projekten der Projektgruppe nirgends verwendet. Die Suche läuft projektweit über den Symbolindex: Nur Dateien, deren Verwendungen im Index den Namen enthalten, werden gelesen, und jedes Vorkommen wird über die Namensauflösung zugeordnet; ein Vorkommen, das sich nicht auflösen lässt, zählt als Verwendung. Namen in Formulardateien (.dfm/.fmx) und in String-Literalen zählen als Verwendung. Gelten als verwendet: Interface-Umsetzungen und Mitglieder von Interfaces, Methoden mit virtual, dynamic, override, abstract oder message, Konstruktoren, Destruktoren, Operatoren, Enumeratoren, Default-Properties, implements, Mitglieder mit Attributen, published-Mitglieder von TPersistent-Nachfahren (Streaming), von Klassen aus RegisterComponents, RegisterClass oder RegisterClasses und von Testklassen, published-Methoden, solange eine Formulardatei nicht lesbar ist, Property-Zugriffsmethoden, exportierte Routinen, Klassenhelfer und Mitglieder von Klassen mit unbekanntem Vorfahren. Still, solange Projekte laden oder der Index unvollständig ist, wenn eine Datei nicht lesbar ist, bei Units mit Include-Dateien und bei Units von Packages oder Bibliotheken (Nutzer außerhalb des Projekts), außer projectKinds lässt sie zu. Korrektur: als bewusst öffentlich markieren (lsp-ignore-Kommentar).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `visibilities` | string-list | `["public","published"]` | Geprüfte Sichtbarkeiten: public, published, protected. |
| `memberKinds` | string-list | `["method","constant","property"]` | Geprüfte Mitgliedsarten: method, constant, property, field, classVar. |
| `projectKinds` | string-list | `["application"]` | Projektarten, deren Units geprüft werden: application, package, library. Packages und Bibliotheken haben Nutzer außerhalb der Projektgruppe und sind deshalb standardmäßig aus. |
| `unitLevel` | boolean | `true` | Auch Routinen und Konstanten aus dem interface-Abschnitt einer Unit prüfen. |
| `scope` | string | `"projectGroup"` | Wo nach Verwendungen gesucht wird: projectGroup (alle Projekte der Gruppe) oder project (nur die Projekte der Datei). |
| `testsCountAsUse` | boolean | `true` | Verwendungen in Testprojekten zählen; ist es aus, wird ein Mitglied, das nur Tests verwenden, als solches gemeldet. |
| `stringLiteralsCountAsUse` | boolean | `true` | Der Name als String-Literal ('Name') zählt als Verwendung (RTTI, MethodAddress, Skripte). |
| `keepAttributes` | string-list | `[]` | Attribute am Mitglied oder seinem Typ, die es als verwendet markieren, z. B. "Keep" oder "Api". |
| `keepPatterns` | string-list | `[]` | Namensmuster (* und ?) für Mitglieder, die immer als verwendet gelten, z. B. "TPlugin.*" oder "*Callback". |

Mit Treffer:

```pascal
  TExport = class
  public
    procedure ExportiereAlsXml;
  end;
// ExportiereAlsXml is called nowhere in the project group
```

Richtig:

```pascal
  TExport = class
  public
    procedure ExportiereAlsJson; // called by TMainForm
  end;
```

<a id="message-method-invalid"></a>
### message-method-invalid

**message-Methode falsch deklariert** · Bug · Fehler · Gruppe Compiler vorab

Eine message-Prozedur einer Klasse hat nicht genau einen var-Parameter (wie E2138; der Typ wird nicht geprüft, ein untypisierter var-Parameter ist in Ordnung), ihre Nachrichtennummer ist kleiner als 1 (wie E2139) oder eine frühere message-Methode derselben Klasse behandelt schon dieselbe Nummer (wie E2140, meist nach Kopieren). Nummern gelten als gleich, wenn ihre Werte bekannt sind (Zahlen, Konstanten aus dem Index) oder die Ausdrücke gleich lauten. Methoden in sich ausschließenden {$IF}-Zweigen sind nicht doppelt; dieselbe Nummer in einem Nachfahren überschreibt den Handler und ist erlaubt. Korrektur für E2138: einen einzelnen Parameter zu var machen, sonst die Liste durch (var Msg: TMessage) ersetzen; der Rumpf in derselben Datei wird mit angepasst.

Entspricht der Compilermeldung `E2138`, `E2139`, `E2140`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
procedure WMSize(var Msg: TWMSize); message WM_SIZE;
procedure WMGroesse(var Msg: TWMSize); message WM_SIZE;
```

Richtig:

```pascal
procedure WMSize(var Msg: TWMSize); message WM_SIZE;
procedure WMMove(var Msg: TWMMove); message WM_MOVE;
```

<a id="interface-declaration-invalid"></a>
### interface-declaration-invalid

**Unzulässige Deklaration in einem Interface** · Bug · Fehler · Gruppe Compiler vorab

Ein Interface deklariert etwas, das Interfaces nicht haben dürfen: Felder (wie E2209), Sichtbarkeitsabschnitte oder Methodendirektiven wie virtual, dynamic, abstract, override, message oder reintroduce (wie E2210), die Property-Klauseln stored, nodefault oder default mit Wert (wie E2207; default; hinter einer Array-Property ist erlaubt), eine Property, die ein Vorfahr-Interface schon deklariert (wie E2206), oder einen Property-Accessor, den nur das Vorfahr-Interface deklariert (wie E2370). Ebenso gemeldet werden eine Klasse, ein Record oder eine Aufzählung als Vorfahr eines Interfaces oder in der Interface-Liste einer Klasse (wie E2205) und dasselbe Interface zweimal in dieser Liste (wie E2208). Typen werden über die uses-Klauseln aufgelöst; Aliase, unbekannte Typen, dispinterface und Deklarationen in bedingten Zweigen bleiben still.

Entspricht der Compilermeldung `E2205`, `E2206`, `E2207`, `E2208`, `E2209`, `E2210`, `E2370`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
IKunde = interface
  FName: string;
  function GetName: string;
end;
```

Richtig:

```pascal
IKunde = interface
  function GetName: string;
  property Name: string read GetName;
end;
```

<a id="implements-clause-invalid"></a>
### implements-clause-invalid

**implements-Klausel unzulässig** · Bug · Fehler · Gruppe Compiler vorab

Eine Delegation mit implements verletzt eine ihrer festen Regeln: implements nur in Klassen (wie E2258), nur an Properties mit Klassen- oder Interface-Typ (wie E2259; gemeldet für eingebaute Typen, Records und Aufzählungen), nicht zusammen mit index (wie E2260), nur an lesbaren Properties (wie E2261), der Getter ohne andere Aufrufkonvention als register (wie E2262) und nicht dynamic oder message (wie E2263), jedes Interface nur über eine Property (wie E2257) und keine Methodenzuordnung für ein so umgesetztes Interface (wie E2264). Typen werden über die uses-Klauseln aufgelöst; unbekannte Typen, Aliase und Properties in bedingten Zweigen bleiben still.

Entspricht der Compilermeldung `E2257`, `E2258`, `E2259`, `E2260`, `E2261`, `E2262`, `E2263`, `E2264`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
property Logger: ILogger write FLogger implements ILogger;
```

Richtig:

```pascal
property Logger: ILogger read FLogger write FLogger implements ILogger;
```

<a id="calling-convention-required"></a>
### calling-convention-required

**Aufrufkonvention passt nicht** · Bug · Fehler · Gruppe Compiler vorab

Der Compiler schreibt hier die Aufrufkonvention vor: Konstruktoren und Destruktoren einer Klasse nur mit register (wie E2236), Getter und Setter von published-Properties ebenso (wie E2270) und varargs nur mit cdecl (wie E2277 bei external-Routinen, sonst E2591). Ein ausdrückliches register ist in Ordnung; Klassenkonstruktoren, Accessoren außerhalb von published-Abschnitten und geerbte Accessoren bleiben still. Korrektur: die Konvention in der Deklaration und im Rumpf derselben Datei entfernen bzw. bei varargs cdecl setzen.

Entspricht der Compilermeldung `E2236`, `E2270`, `E2277`, `E2591`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
function Formatieren(Muster: PAnsiChar): Integer; stdcall; varargs; external 'msvcrt.dll';
```

Richtig:

```pascal
function Formatieren(Muster: PAnsiChar): Integer; cdecl; varargs; external 'msvcrt.dll';
```

<a id="abstract-declaration-invalid"></a>
### abstract-declaration-invalid

**abstract, final oder static falsch kombiniert** · Bug · Fehler · Gruppe Compiler vorab

Eine Methodendirektive, die der Compiler ablehnt: abstract ohne virtual, dynamic oder override (wie E2167), ein Rumpf im implementation-Teil zu einer abstrakten Methode (wie E2136), final an einer nicht virtuellen Methode (wie E2351), abstract zusammen mit final (wie E2371), eine Klasse abstract sealed (wie E2383, E2540) oder static an einer Instanzmethode bzw. einer virtuellen Klassenmethode (wie E2376). Ein Rumpf zählt nur dann als Rumpf einer abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben Klasse mit ihm übersetzt wird (Überladungen, {$IFDEF}-Zweige). Korrekturen: virtual; vor abstract einfügen, Rumpf entfernen.

Entspricht der Compilermeldung `E2167`, `E2136`, `E2351`, `E2371`, `E2383`, `E2540`, `E2376`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
TForm = class
  function Flaeche: Double; abstract;
end;
```

Richtig:

```pascal
TForm = class
  function Flaeche: Double; virtual; abstract;
end;
```

<a id="unsatisfied-forward"></a>
### unsatisfied-forward

**Vorwärtsdeklaration nie aufgelöst** · Bug · Fehler · Gruppe Compiler vorab

Eine Routine aus dem interface-Teil oder mit forward hat keinen Rumpf (wie E2065), oder eine Vorwärtsdeklaration TFoo = class; bzw. IFoo = interface; wird im selben type-Abschnitt nie vollständig deklariert (wie E2086, E2420). Methoden prüft declared-not-implemented. Ein Rumpf passt, wenn er gleich heißt; bei overload muss auch die Zahl der Parameter stimmen. Ein external im implementation-Teil zählt als Rumpf. Deklarationen in einem {$IFDEF}-Zweig bleiben unbeachtet; mit Include-Dateien prüft die Regel keine Routinen. Korrektur: leeren Rumpf vor initialization bzw. dem abschließenden end. anlegen.

Entspricht der Compilermeldung `E2065`, `E2086`, `E2420`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
interface

function Pruefsumme(const Daten: TBytes): Cardinal;

implementation

end.
```

Richtig:

```pascal
interface

function Pruefsumme(const Daten: TBytes): Cardinal;

implementation

function Pruefsumme(const Daten: TBytes): Cardinal;
begin
  Result := 0;
end;

end.
```

<a id="member-hides-ancestor"></a>
### member-hides-ancestor

**Member verdeckt einen Member des Vorfahren** · Bug · Warnung · Gruppe Compiler vorab

Eine Property heißt wie ein Feld eines Vorfahren (wie W1009), ein Feld wie ein Feld oder eine Property eines Vorfahren oder eine nicht virtuelle Methode hat Namen und Parameter einer nicht virtuellen Methode eines Vorfahren. Code, der über den Vorfahrtyp zugreift, sieht weiter den alten Member. Virtuelle Methoden meldet hides-virtual, lokale Namen shadowed-name. Neu veröffentlichte Properties (property Caption;), Properties mit neuem Typ über einer Property des Vorfahren, overload, reintroduce, Konstruktoren und Klassenmethoden bleiben unbeanstandet. Member, die der Nachfahre nicht sieht (private einer anderen Unit, strict private mit ignoreStrictPrivate), zählen nicht; Vorfahren kommen aus der Datei und dem Symbolindex. Korrektur für Felder und Properties: den Member in der Klassendeklaration und in den Rümpfen ihrer Methoden in dieser Unit umbenennen (aus FName wird FKundeName).

Entspricht der Compilermeldung `W1009`.

Stufe B (Namensauflösung über Units).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignoreStrictPrivate` | boolean | `true` | Verdeckte strict private Member des Vorfahren nicht melden. |

Mit Treffer:

```pascal
TBasis = class
  FName: string;
end;
TKunde = class(TBasis)
  FName: string;
end;
```

Richtig:

```pascal
TBasis = class
  FName: string;
end;
TKunde = class(TBasis)
  FKundeName: string;
end;
```

<a id="published-type-invalid"></a>
### published-type-invalid

**Unzulässiges Mitglied im published-Abschnitt** · Bug · Fehler · Gruppe Compiler vorab

Ein Mitglied hinter einem ausdrücklichen published, das der Compiler ablehnt: eine Property vom Typ Record, Array, Zeiger oder Prozedurtyp ohne of object (wie E2188), vom Typ Real48 (wie E2186) oder eine Menge über 4 Byte (wie E2187), ein Feld, das weder Klasse noch Interface ist (wie E2217), mehr als eine published-Überladung (wie E2266), eine Klassen-Property (wie E2545) oder ein Name mit Zeichen außerhalb von ASCII (wie E2452). Typen löst die Regel über die Datei und den Index auf und verfolgt Aliase; Typparameter, unbekannte Typen und Abschnitte, deren published in einem anderen Zweig der bedingten Übersetzung steht als das Mitglied, bleiben still. Den Abschnitt ohne Sichtbarkeitsangabe prüft sie nicht, weil der Compiler solche Mitglieder dort still zu public herabstuft. Korrektur: das Mitglied in den public-Abschnitt verschieben.

Entspricht der Compilermeldung `E2188`, `E2217`, `E2186`, `E2187`, `E2266`, `E2545`, `E2452`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TKarte = class(TCustomControl)
published
  property Mitte: TPointF read FMitte write SetMitte;
end;
```

Richtig:

```pascal
TKarte = class(TCustomControl)
public
  property Mitte: TPointF read FMitte write SetMitte;
end;
```

<a id="override-case-mismatch"></a>
### override-case-mismatch

**Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab** · Code Smell · Hinweis · Gruppe Compiler vorab

Eine überschreibende Methode schreibt ihren Namen anders als der Vorfahr (destructor destroy, wie H2365) oder ist weniger sichtbar als die überschriebene Methode (wie H2269, nur für Klassen im interface-Teil; verglichen werden die Stufen privat, geschützt, öffentlich), ein Getter oder Setter heißt Get<Property> bzw. Set<Property>, ist aber anders geschrieben (wie H2367), oder eine inline-Methode greift auf ein Mitglied zu, das weniger sichtbar ist als sie selbst, sodass der Compiler sie außerhalb der Klasse nicht einsetzen kann (wie H2440). Wichtig für C++Builder-Nutzer der Units und für einheitlichen Code. Die Docwiki führt H2269 und H2367 als X2269 und X2367, weil sich ihre Stufe umstellen lässt; dcc meldet sie standardmäßig als Hinweis. H2368 und H2369 deckt die Regel nicht ab, weil nicht dokumentiert ist, wann dcc sie meldet. Standardmäßig aus; in atlas.json einschalten. Korrekturen: Schreibweise vom Vorfahr übernehmen, Zugriffsmethode umbenennen.

Entspricht der Compilermeldung `H2365`, `H2440`, `H2269`, `H2367`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TKunde = class
  destructor destroy; override;
end;
```

Richtig:

```pascal
TKunde = class
  destructor Destroy; override;
end;
```

<a id="default-property-invalid"></a>
### default-property-invalid

**default-Property falsch deklariert oder fehlt** · Bug · Fehler · Gruppe Compiler vorab

default; hinter einer Property ohne Indexparameter (wie E2132), eine zweite default-Property derselben Klasse mit denselben Indextypen (wie E2131; Überladung über den Indextyp ist erlaubt) oder Obj[I] auf einer Klasse, die in ihrer ganzen Vorfahrenkette keine default-Property hat (wie E2149). Den Typ von Obj ermittelt die Namensauflösung; nicht auflösbare Typen, abgebrochene Vorfahrenketten und Klassen mit einem Class-Helper in der Unit bleiben still. Neudeklarationen ohne Typ (property Items; default;) übernehmen den Index des Vorfahren und werden nicht geprüft.

Entspricht der Compilermeldung `E2131`, `E2132`, `E2149`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TListe = class
  property Name: string read FName; default;
end;
```

Richtig:

```pascal
TListe = class
  property Items[I: Integer]: string read GetItem; default;
end;
```

<a id="property-redeclaration-invalid"></a>
### property-redeclaration-invalid

**Neu deklarierte Property fehlt im Vorfahren** · Bug · Fehler · Gruppe Compiler vorab

Eine Neudeklaration ohne Typ wie property Caption; (um Sichtbarkeit oder Standardwert zu ändern) nennt eine Property, die kein Vorfahr hat (wie E2147), oder die Property des Vorfahren ist von hier aus nicht erreichbar: strict private oder private in einer anderen Unit (wie E2233). Gemeldet nur, wenn die ganze Vorfahrenkette bekannt ist; ein gleichnamiges Feld oder eine Methode und Deklarationen in inaktiven Zweigen bleiben still. Korrektur: den ähnlichsten Property-Namen der Vorfahren verwenden.

Entspricht der Compilermeldung `E2147`, `E2233`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
TMeinPanel = class(TCustomPanel)
published
  property Captoin;
end;
```

Richtig:

```pascal
TMeinPanel = class(TCustomPanel)
published
  property Caption;
end;
```

<a id="inline-not-expanded"></a>
### inline-not-expanded

**Inline-Funktion wird nicht eingebettet** · Code Smell · Hinweis · Gruppe Compiler vorab

Aufruf einer inline-Routine aus einer anderen Unit, die der Compiler nicht einbettet: Ihr Rumpf braucht eine Unit, die hier in uses fehlt (wie H2443, typisch System.Generics.Collections bei TJSONObject.Count), er greift auf ein strict private-Mitglied zu und der Aufruf steht nicht in einer Methode dieser Klasse (wie H2444), die aufrufende Routine ist selbst inline und die Unit der gerufenen steht nur im uses des implementation-Teils (wie H2445), oder die Unit der gerufenen Routine verwendet diese Unit direkt (wie H2456) bzw. über andere Units (wie H2457). Geprüft werden Aufrufe, Properties mit inline-Getter bzw. -Setter und for-in (GetEnumerator, MoveNext, Current). Der Index merkt sich, worauf jeder inline-Rumpf verweist; die Regel meldet nur, was sie sicher auflöst (unbekannte Verweise und geerbte Mitglieder aus anderen Units bleiben stumm). Mit {$INLINE OFF} in der Datei schweigt sie. Korrektur: die fehlenden Units in das uses des Abschnitts aufnehmen.

Entspricht der Compilermeldung `H2443`, `H2444`, `H2445`, `H2456`, `H2457`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
uses
  System.JSON;
...
for Wert in Feld as TJSONArray do
```

Richtig:

```pascal
uses
  System.JSON, System.Generics.Collections;
...
for Wert in Feld as TJSONArray do
```

<a id="directive-typo"></a>
### directive-typo

**Unbekannte Direktive (Tippfehler)** · Bug · Fehler · Gruppe Compiler vorab

An der Stelle einer Direktive steht ein Wort, das keine ist: nach dem ';' eines Routinen- oder Methodenkopfs (overide;, virutal;, overlaod;, stdcal;, reintroduces;) oder nach einer Property, wo nur default erlaubt ist (defualt;). Der Compiler bricht dort ab (wie E2070). Die Meldung schlägt die ähnlichste Direktive vor, wenn höchstens zwei Zeichen abweichen. Still in {$IF}-Zweigen, die FPC abfragen; FPC kennt weitere Direktiven wie nostackframe. Korrektur: durch die vorgeschlagene Direktive ersetzen.

Entspricht der Compilermeldung `E2070`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
procedure Paint; overide;
```

Richtig:

```pascal
procedure Paint; override;
```

<a id="ui-call-in-console-or-service"></a>
### ui-call-in-console-or-service

**Dialog in Konsolenprogramm oder Dienst** · Bug · Warnung · Gruppe Robustheit und Muster

ShowMessage, ShowMessageFmt, MessageDlg, TaskMessageDlg, InputBox, InputQuery, Application.MessageBox oder TDialogService in einem Programm mit {$APPTYPE CONSOLE} (oder DCC_ConsoleTarget in der .dproj), in einem Windows-Dienst oder in einer DLL ohne Formulare. Im Dienst blockiert der Dialog unsichtbar; ein Konsolenprogramm wartet auf einen Klick, den niemand sieht, wenn es unbeaufsichtigt läuft. Als Dienst gilt eine Unit mit einer Klasse, die von TService erbt, oder jede Unit eines Projekts, dessen .dpr Vcl.SvcMgr ohne Vcl.Forms einbindet. Eine DLL ohne Formulare ist eine library, deren .dpr kein Formular aufführt und Vcl.Forms nicht einbindet; dort meldet die Regel mit mittlerer Konfidenz, weil erst der Host entscheidet, ob es eine Oberfläche gibt. Units mit Formulardatei, Aufrufe unter if IsConsole und gleichnamige Routinen der Unit bleiben still. Gegenstück zu writeln-in-gui-app. Konfidenz hoch. Keine Schnellkorrektur: die Meldung protokollieren statt anzeigen.

Mit Treffer:

```pascal
procedure TDatenDienst.ServiceExecute(Sender: TService);
begin
  if not Verbinden then
    ShowMessage('Keine Verbindung');
end;
```

Richtig:

```pascal
procedure TDatenDienst.ServiceExecute(Sender: TService);
begin
  if not Verbinden then
    LogMessage('Keine Verbindung', EVENTLOG_ERROR_TYPE);
end;
```

<a id="load-without-encoding"></a>
### load-without-encoding

**Text laden oder speichern ohne Kodierung** · Bug · Warnung · Gruppe Robustheit und Muster

LoadFromFile, SaveToFile, LoadFromStream oder SaveToStream einer TStrings (TStringList, Memo.Lines, ListBox.Items, Query.SQL) sowie TFile.ReadAllText und TFile.ReadAllLines ohne Kodierung: Eine Datei ohne BOM wird mit der ANSI-Codepage des Rechners gelesen, SaveToFile schreibt ANSI, und Umlaute gehen zwischen Rechnern verloren. Der Empfänger muss eine deklarierte Stringliste oder eine Property Lines, Items, SQL oder Strings sein; Bilder, Streams und Datenmengen bleiben still. Ebenso still, wenn die Liste irgendwo in der Unit DefaultEncoding setzt oder in derselben Routine vorher mit Kodierung geladen wurde (SaveToFile behält diese Kodierung). TFile.WriteAllText, TStreamReader und TStreamWriter nehmen ohne Angabe schon UTF-8 und werden nicht gemeldet. Konfidenz mittel. Schnellkorrektur: TEncoding.UTF8 (Option defaultEncoding) als letztes Argument und System.SysUtils im uses ergänzen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `defaultEncoding` | string | `"UTF8"` | Property von TEncoding, die die Schnellkorrektur einsetzt: UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default. |

Mit Treffer:

```pascal
Zeilen.LoadFromFile(Pfad);
```

Richtig:

```pascal
Zeilen.LoadFromFile(Pfad, TEncoding.UTF8);
```

<a id="registry-hklm-write"></a>
### registry-hklm-write

**Schreiben nach HKEY_LOCAL_MACHINE** · Bug · Hinweis · Gruppe Robustheit und Muster

RootKey := HKEY_LOCAL_MACHINE auf einer TRegistry, danach in derselben Routine ein schreibender Zugriff auf dasselbe Objekt: OpenKey(…, True), CreateKey, Write…, DeleteKey, DeleteValue, RenameValue, MoveKey, SaveKey oder RestoreKey. Ohne Administratorrechte schlägt das fehl oder landet still in der Virtualisierung der Registry. Für Benutzereinstellungen HKEY_CURRENT_USER verwenden; Installer-Code über exclude ausnehmen. Lesen (OpenKeyReadOnly, Read…, OpenKey(…, False)), ein anderer RootKey vor dem Schreiben und Schreiben im anderen Zweig von {$IFDEF} bleiben still. Konfidenz hoch. Schnellkorrektur: RootKey := HKEY_CURRENT_USER.

Mit Treffer:

```pascal
Reg.RootKey := HKEY_LOCAL_MACHINE;
Reg.OpenKey('Software\Firma\Programm', True);
Reg.WriteString('Sprache', Sprache);
```

Richtig:

```pascal
Reg.RootKey := HKEY_CURRENT_USER;
Reg.OpenKey('Software\Firma\Programm', True);
Reg.WriteString('Sprache', Sprache);
```

<a id="now-for-elapsed-time"></a>
### now-for-elapsed-time

**Laufzeit mit Now gemessen** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Variable, der Now zugewiesen wird und die in derselben Routine danach in Now - Start, Ende - Start oder MilliSecondsBetween, SecondsBetween, MinutesBetween, HoursBetween, DaysBetween bzw. den …Span-Funktionen vorkommt: Die Laufzeit wird mit der Uhrzeit gemessen, grob aufgelöst und falsch bei Zeitumstellung oder Uhrabgleich. TStopwatch ist genau und monoton. Zuweisungen in einer anderen Routine (Felder) und im anderen Zweig von {$IFDEF} bleiben still. Konfidenz hoch. Schnellkorrektur, wenn die Variable eine lokale TDateTime ist (auch var Start := Now) und nur für MilliSecondsBetween, SecondsBetween oder MinutesBetween mit Now dient: TStopwatch.StartNew und ElapsedMilliseconds (div 1000 bzw. div 60000), die Variable heißt danach Uhr, wenn der Name frei ist, System.Diagnostics kommt ins uses.

Mit Treffer:

```pascal
Start := Now;
Importieren;
Log(MilliSecondsBetween(Now, Start).ToString + ' ms');
```

Richtig:

```pascal
Uhr := TStopwatch.StartNew;
Importieren;
Log(Uhr.ElapsedMilliseconds.ToString + ' ms');
```

<a id="money-as-float"></a>
### money-as-float

**Geldbetrag als Gleitkommazahl** · Bug · Hinweis · Gruppe Stil und Metriken

Feld, Variable, Parameter oder Property, deren Name einen Geldbetrag bezeichnet (Option namePatterns), mit dem Typ Double, Single, Extended oder Real: Binäres Gleitkomma rundet Cent-Beträge falsch (0.1 + 0.2), Currency rechnet sie exakt. Maßgeblich ist der letzte Namensteil (GesamtPreis, Nettobetrag, FNetto, Preise; nicht NettoGewicht); Sätze, Faktoren, Quoten, Anteile (Steuersatz, PriceFactor) und Prüfsummen bleiben still. Mehrdeutige Wörter (Amount, Summe, Sum, Total: Menge bzw. Summe von irgendetwas) zählen nur mit Geldbezug in Typ bzw. Routine: ein anderer Geldname, Currency oder Wörter wie Cent, Euro, Rabatt, Rechnung, Zahlung, Kosten (Lighten(AColor, AAmount: Double) bleibt still). Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur, wenn alle Namen der Deklaration Geldbeträge sind: Typ Currency, bei Parametern auch im Kopf der Implementierung, bei Feldern und Properties auch die Property bzw. das Feld hinter read und write; keine Korrektur, wenn ein Getter oder Setter mitwandern müsste. Mit checkRound meldet die Regel zusätzlich Round mit einem Geldbetrag im Argument (Banker's Rounding: 2,5 wird 2).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `namePatterns` | string-list | `["Betrag","Preis","Summe","Netto","Brutto","Steuer","Amount","Price"]` | Namensteile, die einen Geldbetrag bezeichnen; Mehrzahl eingeschlossen. |
| `checkRound` | boolean | `false` | Zusätzlich Round auf Geldbeträgen melden. |

Mit Treffer:

```pascal
TPosition = record
  Menge: Integer;
  Preis: Double;
end;
```

Richtig:

```pascal
TPosition = record
  Menge: Integer;
  Preis: Currency;
end;
```

<a id="string-if-chain"></a>
### string-if-chain

**Lange if-Kette über denselben String** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine if … else if-Kette vergleicht denselben String (Bezeichner oder A.B, keine Funktionsaufrufe) mit mindestens min Literalen: S = 'x', 'x' = S, SameText(S, 'x'), auch mit or verknüpft, in mindestens zwei Zweigen (ein einzelnes if mit or bleibt still). case IndexStr(S, [...]) of oder ein Dictionary ist kürzer und schneller. Es zählen nur Vergleiche, die immer zusammen mit dem Kopf übersetzt werden ({$IFDEF}-Zweige innerhalb der Kette nicht). Standard aus, Konfidenz hoch. Schnellkorrektur wie die Code-Aktion if-Kette in case umwandeln (#646): case IndexStr(…) of, IndexText(…) bei SameText, mit or verknüpfte Vergleiche teilen sich eine Marke, der Rest der Kette wird zum else, System.StrUtils kommt ins uses. Keine Korrektur bei Kommentaren oder Direktiven zwischen den Zweigen, doppelten Literalen oder gemischtem = und SameText.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `min` | integer | `4` | Ab so vielen Vergleichen desselben Strings meldet die Regel; mindestens 2. |

Mit Treffer:

```pascal
if Befehl = 'neu' then Neu
else if Befehl = 'oeffnen' then Oeffnen
else if Befehl = 'speichern' then Speichern
else if Befehl = 'beenden' then Beenden;
```

Richtig:

```pascal
case IndexStr(Befehl, ['neu', 'oeffnen', 'speichern', 'beenden']) of
  0: Neu;
  1: Oeffnen;
  2: Speichern;
  3: Beenden;
end;
```

<a id="constant-condition"></a>
### constant-condition

**Bedingung ist immer gleich** · Bug · Warnung · Gruppe Fehler finden

Die Bedingung von if, while oder until steht fest: True, False, Vergleiche von Zahlen und untypisierte Konstanten der Datei, auch über and, or, xor und not (X or True ist immer wahr, X and False immer falsch). Der Zweig ist toter Code oder läuft immer. while True do und repeat … until False gelten als gewollte Endlosschleifen (deren Ausgang prüft infinite-loop). Konstanten aus switchConstants, Konstanten in einem Zweig von {$IF…} und Konstanten aus anderen Units gelten als unbekannt. Korrektur bei if: toten Zweig bzw. die Bedingung entfernen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `switchConstants` | string-list | `[]` | Konstanten, die bewusst als Schalter dienen; Bedingungen darauf werden nicht gemeldet. |

Mit Treffer:

```pascal
if (Count > 0) or True then
  Process;
```

Richtig:

```pascal
if Count > 0 then
  Process;
```

<a id="infinite-loop"></a>
### infinite-loop

**Schleife ohne Ausgang** · Bug · Fehler · Gruppe Fehler finden

while True do, repeat … until False oder eine andere Schleife, deren Bedingung sie nie beendet, ohne Ausgang im Rumpf: kein Break (ein Break in einer inneren Schleife verlässt nur diese), Exit, raise, goto, Halt, Abort oder RunError, kein Aufruf einer Routine der Datei, die eine Ausnahme auslöst oder das Programm beendet, und keine Prüfung von Terminated (Thread-Schleifen prüft thread-loop-without-terminated). Anonyme Methoden im Rumpf zählen nicht. Die Aktion springt zum Schleifenkopf.

Mit Treffer:

```pascal
while True do
begin
  Line := Reader.ReadLine;
  Process(Line);
end;
```

Richtig:

```pascal
while not Reader.EndOfStream do
begin
  Line := Reader.ReadLine;
  Process(Line);
end;
```

<a id="loop-condition-unchanged"></a>
### loop-condition-unchanged

**Schleifenbedingung ändert sich im Rumpf nie** · Bug · Warnung · Gruppe Fehler finden

Keine Variable der while- bzw. until-Bedingung ändert sich im Rumpf: keine Zuweisung, kein Inc/Dec, kein Argument (möglicherweise var), kein Methoden- oder Mitgliedszugriff auf das Objekt der Bedingung, keine for-Schleife darüber. Typisch ist das vergessene Inc(I) oder Next. Gemeldet wird nur, wenn jede Variable der Bedingung eine lokale Variable oder ein Wertparameter der Routine ist und mindestens eine direkt (nicht nur als X.Eigenschaft) vorkommt. Still bleiben Bedingungen mit Funktionsaufrufen, Feldern, globalen Variablen, var- und out-Parametern und Terminated, außerdem Schleifen mit Ausgang (Break, Exit, raise …), Warteschleifen (Sleep, ProcessMessages …), with, Aufrufen lokaler Routinen und Variablen, die eine anonyme Methode erfasst. Änderungen über X[…] zählen nur, wenn die Bedingung X[…] liest.

Mit Treffer:

```pascal
I := 0;
while I < List.Count do
begin
  Check(List[I]);
end;
```

Richtig:

```pascal
I := 0;
while I < List.Count do
begin
  Check(List[I]);
  Inc(I);
end;
```

<a id="loop-runs-at-most-once"></a>
### loop-runs-at-most-once

**Schleife läuft höchstens einmal** · Bug · Warnung · Gruppe Fehler finden

Jeder Weg durch den Rumpf einer for-, for-in-, while- oder repeat-Schleife endet mit Exit, Break, raise, Halt, Abort, RunError, ExitProcess oder dem Aufruf einer Routine der Datei, die eine Ausnahme auslöst; die Schleife läuft also höchstens einmal. Meist fehlt ein if vor dem Sprung, oder ein Continue war gemeint. Ein Weg zählt als Sprung bei if mit else und beiden Zweigen, case mit else und allen Zweigen, try … finally mit try- oder finally-Teil und try … except mit try-Teil und jedem Behandler. Still bei Continue dieser Schleife, goto bzw. Marken und bedingten Direktiven im Rumpf; ein Break innerer Schleifen zählt nicht. Ergänzt infinite-loop und loop-condition-unchanged. Keine Korrektur, die Absicht ist unklar; steht der Sprung direkt hinter einem if ohne else, fragt die Meldung, ob er in den if-Zweig gehört. Sicherheit hoch.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowFirstElement` | boolean | `false` | for-in aus einfachen Anweisungen, das mit Exit bzw. Break endet (erstes Element holen), nicht melden. |

Mit Treffer:

```pascal
for mCustomer in FCustomers do
begin
  if mCustomer.Id = AId then
    Result := mCustomer;
  Exit;
end;
```

Richtig:

```pascal
for mCustomer in FCustomers do
  if mCustomer.Id = AId then
    Exit(mCustomer);
```

<a id="unconditional-recursion"></a>
### unconditional-recursion

**Rekursion ohne Abbruch** · Bug · Fehler · Gruppe Fehler finden

Eine Routine ruft sich auf jedem Pfad selbst auf, bevor sie zurückkehren kann: Es gibt keinen Pfad ohne Selbstaufruf und kein Exit oder raise davor. Ergebnis ist ein Stapelüberlauf. Pfade ohne Aufruf sind: if ohne else bzw. case ohne else, der Rumpf von while und for, die rechte Seite von and/or, Zweige von if-Ausdrücken und anonyme Methoden. Getter und Setter der eigenen Property meldet setter-recursion; überladene Routinen bleiben still (der Aufruf kann eine andere Überladung treffen). Das Randsymbol aus #623 zeigt jede Rekursion.

Mit Treffer:

```pascal
function TTree.Depth(N: TNode): Integer;
begin
  Result := 1 + Max(Depth(N.Left), Depth(N.Right));
end;
```

Richtig:

```pascal
function TTree.Depth(N: TNode): Integer;
begin
  if N = nil then
    Exit(0);
  Result := 1 + Max(Depth(N.Left), Depth(N.Right));
end;
```

<a id="pos-arguments-swapped"></a>
### pos-arguments-swapped

**Argumente von Pos vertauscht** · Bug · Warnung · Gruppe Fehler finden

Pos(Text, ';'): Pos, PosEx, AnsiPos, StartsText, StartsStr, EndsText und EndsStr (auch mit Ansi-Präfix) erwarten zuerst den gesuchten Teil, dann den Text; ContainsText und ContainsStr erwarten zuerst den Text. Gemeldet, wenn an der Stelle des Textes ein kurzes Literal steht (bis maxLiteralLength Zeichen, Vorgabe 3; '' zählt als ein Zeichen, #9 ebenso) und an der Stelle des Teils sicher ein String: eine Variable oder ein Feld mit in der Datei deklariertem String-Typ, .Text oder .Caption, eine String-Funktion der RTL (Trim, UpperCase, LeftStr, Format …) oder eine Verkettung mit einem String-Teil. Zeichen bleiben still, weil Pos(C, ';,') bewusst prüft, ob C einer der Trenner ist; ebenso unbekannte Typen, zwei Literale und Methoden anderer Objekte (Liste.Pos). Konfidenz mittel. Schnellkorrektur: Argumente in einer Änderung tauschen; Kommentare dazwischen bleiben.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `maxLiteralLength` | integer | `3` | Längstes Literal an der Stelle des Textes, das noch als vertauscht gilt. |

Mit Treffer:

```pascal
if Pos(Zeile, ';') > 0 then
```

Richtig:

```pascal
if Pos(';', Zeile) > 0 then
```

<a id="integer-division-to-float"></a>
### integer-division-to-float

**Ganzzahldivision an Gleitkommazahl** · Bug · Warnung · Gruppe Fehler finden

Schnitt := Summe div Anzahl mit Schnitt: Double: div schneidet die Nachkommastellen ab, bevor zugewiesen wird. Ebenso Prozent := Teil div Gesamt * 100, Result einer Funktion mit Gleitkommaergebnis und var X: Double := A div B. Gesucht wird durch Klammern, Vorzeichen und + - * / hindurch, nicht in Aufrufen (Round(A div B)), Indizes, mod oder Vergleichen. Das Ziel muss eine Variable, ein Feld (auch Self.X) oder Result sein, deren Typ Single, Double, Extended, Real, Currency … in der Datei deklariert ist. TDateTime, TDate und TTime bleiben still (ganze Tage sind dort meist gewollt), ebenso Zuweisungen in with und Trunc(A) div Trunc(B) (auch Round, Floor, Ceil: ausdrücklich gewandelt, also gewollt ganzzahlig). Konfidenz hoch. Schnellkorrektur: div durch / ersetzen (gleicher Vorrang).

Mit Treffer:

```pascal
var Average: Double;
…
Average := Sum div Count;
```

Richtig:

```pascal
var Average: Double;
…
Average := Sum / Count;
```

<a id="empty-finally"></a>
### empty-finally

**Leerer finally-Block** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein finally-Block ohne Anweisung: Meist ist die Freigabe beim Umbau verloren gegangen. Steht direkt vor try X := T….Create, nennt die Meldung X.Free. Ein Block mit erklärendem Kommentar gilt als bewusst und wird nicht gemeldet (wie bei empty-except); ein Block mit Compiler-Direktive ebenso nicht, weil ein anderer Zweig Code enthalten kann. Konfidenz hoch. Schnellkorrektur: try, finally und end entfernen und den Rumpf ausrücken (wenn try, finally und end je allein auf ihrer Zeile stehen); als einzige Anweisung eines if-, while-, for-, with- oder case-Zweigs mit mehreren Anweisungen im Rumpf wird aus try begin.

Mit Treffer:

```pascal
Liste := TStringList.Create;
try
  Liste.LoadFromFile(Pfad);
finally
end;
```

Richtig:

```pascal
Liste := TStringList.Create;
try
  Liste.LoadFromFile(Pfad);
finally
  Liste.Free;
end;
```

<a id="form-resource-missing"></a>
### form-resource-missing

**Formular-Unit ohne {$R *.dfm}** · Bug · Fehler · Gruppe Formulare und Daten

Neben der Unit liegt eine .dfm bzw. .fmx, die Unit deklariert die Klasse ihres Wurzelobjekts, aber keine {$R …}-Direktive bindet eine Formulardatei ein: Beim Erzeugen des Formulars folgt EResNotFound. Umgekehrt meldet die Regel ein {$R *.dfm} bzw. {$R Name.dfm}, dessen Datei neben der Unit fehlt (der Compiler bricht mit F1026 ab). Eine Direktive in einem beliebigen Zweig der bedingten Übersetzung zählt als eingebunden. Still bleibt die Regel, wenn die Klasse der Formulardatei nicht in der Unit steht und wenn sie keine Dateien neben der Unit sieht. Korrektur: {$R *.dfm} (bzw. {$R *.fmx}) nach implementation einfügen.

Entspricht der Compilermeldung `F1026`.

Mit Treffer:

```pascal
implementation

procedure TfrmKunde.FormShow(Sender: TObject);
```

Richtig:

```pascal
implementation

{$R *.dfm}

procedure TfrmKunde.FormShow(Sender: TObject);
```

<a id="form-autocreate-and-manual"></a>
### form-autocreate-and-manual

**Formular automatisch und zusätzlich von Hand erzeugt** · Bug · Warnung · Gruppe Formulare und Daten

Die .dpr erzeugt ein Formular mit Application.CreateForm, der Code weist derselben globalen Variablen zusätzlich TfrmX.Create(…) zu. Es gibt dann zwei Instanzen, die erste bleibt unsichtbar im Speicher. Die automatisch erzeugten Formulare kommen aus der .dpr des Projekts, zu dem die Unit gehört; kann die Regel die .dpr lesen, muss die Klasse zum CreateForm-Aufruf passen. Still bleibt sie, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil) oder vorher freigibt (Free, FreeAndNil, Release), bei lokalen Namen und gleichnamigen Feldern der eigenen Klasse und bei Units ohne Projekt. Sicherheit hoch. Korrektur: die Zeile mit Application.CreateForm aus der .dpr entfernen (das Formular erzeugt dann nur noch der Code).

Mit Treffer:

```pascal
// Projekt.dpr: Application.CreateForm(TfrmBericht, frmBericht);
frmBericht := TfrmBericht.Create(Application);
frmBericht.ShowModal;
```

Richtig:

```pascal
// Projekt.dpr without CreateForm for TfrmBericht
frmBericht := TfrmBericht.Create(Application);
frmBericht.ShowModal;
```

<a id="inherited-form-handler-without-inherited"></a>
### inherited-form-handler-without-inherited

**Ereignis-Handler im geerbten Formular ohne inherited** · Bug · Warnung · Gruppe Formulare und Daten

Bei Formularvererbung belegt ein Vorfahr-Formular dasselbe Ereignis derselben Komponente mit einem gleichnamigen Handler, der Handler im Nachfahren ruft inherited aber nicht (mehr) auf. Die IDE erzeugt inherited; beim Anlegen; wird es gelöscht, fällt die Logik des Vorfahren still weg. Die Formulardatei des Vorfahren kommt aus dem Index (Datei der Klasse) bzw. aus den Units der uses-Liste neben der Unit; die Kette folgt geerbten Formularen bis zum ersten Formular mit object. Handler mit anderem Namen gelten als bewusster Ersatz. Still ohne Formulardatei des Vorfahren. Sicherheit hoch. Korrektur: inherited; am Anfang einfügen.

Mit Treffer:

```pascal
procedure TfrmKundeBearbeiten.btnSpeichernClick(Sender: TObject);
begin
  FKunde.Speichern;
end;
```

Richtig:

```pascal
procedure TfrmKundeBearbeiten.btnSpeichernClick(Sender: TObject);
begin
  inherited;
  FKunde.Speichern;
end;
```

<a id="self-free-in-event-handler"></a>
### self-free-in-event-handler

**Formular gibt sich im eigenen Ereignis frei** · Bug · Fehler · Gruppe Formulare und Daten

Free, Destroy, DisposeOf oder FreeAndNil auf Self bzw. auf die globale Variable der eigenen Formularklasse als Anweisung in einem Ereignis-Handler des Formulars oder eines seiner Controls. Nach der Rückkehr greift die VCL noch auf das Objekt zu: Zugriffsverletzung. Richtig ist Release oder Action := caFree in OnClose. Ereignis-Handler sind die Methoden aus der Formulardatei und Methoden mit einem Parameter Sender: TObject; ein Formular ist die Wurzelklasse der Formulardatei mit ClientWidth bzw. ClientHeight oder eine direkt von TForm bzw. TCustomForm abgeleitete Klasse (Rahmen und Datenmodule haben kein Release). Anweisungen in anonymen Methoden und with-Blöcken zählen nicht. Still ohne Formulardatei. Sicherheit hoch. Korrektur: Free durch Release ersetzen, in OnClose (var Action: TCloseAction) durch Action := caFree.

Mit Treffer:

```pascal
procedure TfrmMeldung.btnOKClick(Sender: TObject);
begin
  Free;
end;
```

Richtig:

```pascal
procedure TfrmMeldung.btnOKClick(Sender: TObject);
begin
  Release;
end;
```

<a id="parallel-for-shared-write"></a>
### parallel-for-shared-write

**Gemeinsame Variable in TParallel.For geschrieben** · Bug · Warnung · Gruppe Threads

Der Rumpf von TParallel.For bzw. eines TTask.Run/Create/Future, der in einer Schleife entsteht, schreibt eine Variable von außerhalb ohne Sperre: Summe := Summe + …, Inc/Dec oder eine andere Zuweisung, oder er verändert eine Sammlung von außerhalb (Add, Delete, Clear, Insert, Remove …). Die Durchläufe laufen gleichzeitig; Additionen gehen verloren oder die Liste wird beschädigt. Von außerhalb heißt: lokale Variable oder Parameter der umgebenden Routine, Feld ihrer Klasse oder globale Variable der Unit; Namen unbekannter Herkunft bleiben still. Rümpfe mit Sperre (TMonitor, Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked), Zugriffe über Index (Werte[I] := …) und verschachtelte anonyme Methoden (Synchronize, Queue) zählen nicht. Typen aus threadSafeTypes gelten als threadsicher. Sicherheit mittel. Korrekturen: TInterlocked.Add/Increment/Decrement bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs), System.TMonitor.Enter/Exit in try … finally um den Sammlungsaufruf.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `threadSafeTypes` | string-list | `["TThreadList","TThreadedQueue"]` | Typen, die als threadsicher gelten; ihre Sammlungsaufrufe bleiben still. |

Mit Treffer:

```pascal
TParallel.For(0, High(Werte), procedure(I: Integer)
  begin
    Summe := Summe + Werte[I];
  end);
```

Richtig:

```pascal
TParallel.For(0, High(Werte), procedure(I: Integer)
  begin
    TInterlocked.Add(Summe, Werte[I]);
  end);
```

<a id="thread-unsafe-increment"></a>
### thread-unsafe-increment

**Zähler im Thread ohne TInterlocked** · Bug · Warnung · Gruppe Threads

Inc, Dec, X := X + 1 oder X := X - 1 ohne Sperre auf einer globalen Variablen in Execute eines TThread-Nachfahren bzw. auf einem Feld oder einer globalen Variablen im Rumpf von TTask.Run/Create/Future außerhalb von Schleifen und von TThread.CreateAnonymousThread. Inc ist nicht atomar: zählen mehrere Threads gleichzeitig, gehen Erhöhungen verloren. Thread-Klassen kommen aus der Unit (auch über Zwischenklassen) und aus dem Index. Eigene Felder des Threads in Execute und eingefangene lokale Variablen eines einzelnen Tasks haben nur einen Schreiber und bleiben still, ebenso Rümpfe mit Sperre (TMonitor, Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked) und verschachtelte anonyme Methoden (Synchronize, Queue). Tasks in Schleifen und TParallel.For meldet parallel-for-shared-write. Sicherheit mittel. Korrektur: TInterlocked.Increment/Decrement/Add bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs).

Mit Treffer:

```pascal
procedure TArbeiter.Execute;
begin
  while not Terminated do
    if Holen then Inc(GVerarbeitet);
end;
```

Richtig:

```pascal
procedure TArbeiter.Execute;
begin
  while not Terminated do
    if Holen then TInterlocked.Increment(GVerarbeitet);
end;
```

<a id="constant-expression-error"></a>
### constant-expression-error

**Fehler in einem konstanten Ausdruck** · Bug · Fehler · Gruppe Compiler vorab

Ein konstanter Ausdruck teilt durch null (wie E2098), läuft über den Bereich von Int64 und UInt64 hinaus (wie E2099), ein Bereich hat die Untergrenze über der Obergrenze (array[5..1], wie E2011), eine Konstante verletzt einen ganzzahligen Typ fester Größe oder einen Teilbereichstyp (wie W1012, als Warnung; bei Zuweisungen nur Werte außerhalb von 0..127) oder ein Hex-, Binär- oder Oktalliteral braucht mehr als 64 Bit (wie E2102). Atlas wertet Literale, Konstanten (auch aus anderen Units) und SizeOf/High/Low von Typen fester Größe aus; eine Konstante aus einem {$IF}-Zweig zählt nur, wo die geprüfte Stelle mit ihr zusammen übersetzt wird. Ausdrücke mit unbekannten Teilen bleiben still.

Entspricht der Compilermeldung `E2098`, `E2099`, `E2011`, `W1012`, `E2102`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
const
  Seiten = 0;
  ProSeite = 100 div Seiten;
```

Richtig:

```pascal
const
  Seiten = 5;
  ProSeite = 100 div Seiten;
```

<a id="default-parameter-invalid"></a>
### default-parameter-invalid

**Unzulässiger Standardwert eines Parameters** · Bug · Fehler · Gruppe Compiler vorab

Standardwerte, die der Compiler ablehnt: mehrere Namen mit einem gemeinsamen Standardwert (A, B: Integer = 0, wie E2237), ein Parameter ohne Standardwert nach einem mit Standardwert (wie E2238), var- und out-Parameter mit Standardwert (wie E2239) Records oder statische Arrays mit Standardwert (wie E2268) sowie Mengen über 4 Byte mit Standardwert (wie E2146, erlaubt sind nur kleine Mengen; mittlere Konfidenz). Gilt für Routinen, Methoden und Prozedurtypen. Korrekturen: Parameter einzeln deklarieren; Parameter mit Standardwert ans Ende verschieben, auch im zugehörigen Kopf der Deklaration bzw. Implementierung derselben Datei (Aufrufe ändert sie nicht).

Entspricht der Compilermeldung `E2237`, `E2238`, `E2239`, `E2268`, `E2146`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
procedure Senden(const Text: string = ''; Ziel: TZiel);
```

Richtig:

```pascal
procedure Senden(Ziel: TZiel; const Text: string = '');
```

<a id="signed-unsigned-mix"></a>
### signed-unsigned-mix

**Vorzeichenbehaftet und vorzeichenlos gemischt** · Bug · Warnung · Gruppe Compiler vorab

Vergleich oder Rechnung (+, -, *, div, mod) mit einem vorzeichenbehafteten und einem vorzeichenlosen Operanden, deren Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse, eigene Aliase). Mit UInt64 wird der ganze Ausdruck vorzeichenlos gerechnet, ein negativer Wert wird zu einer riesigen Zahl (wie W1073, beim Vergleich wie W1023); mit Cardinal/DWORD und einem vorzeichenbehafteten Typ bis 32 Bit werden beide Operanden auf Int64 erweitert (wie W1023/W1024). Still bei Byte und Word, Cardinal mit Int64, Literalen, Konstanten, NativeInt/NativeUInt und unbekannten Typen. Mittlere Konfidenz. Korrektur: den vorzeichenlosen Operanden in Int64 umwandeln.

Entspricht der Compilermeldung `W1023`, `W1024`, `W1073`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
if Groesse + Delta < Grenze then  // Groesse: UInt64; Delta: Int64
```

Richtig:

```pascal
if Int64(Groesse) + Delta < Grenze then
```

<a id="narrowing-assignment"></a>
### narrowing-assignment

**Zuweisung mit möglichem Datenverlust** · Bug · Warnung · Gruppe Compiler vorab

Eine Zuweisung oder Inline-Variable mit einem Wert, dessen Typ breiter ist als das Ziel, ohne ausdrückliche Umwandlung: Int64 an Integer, NativeInt an Integer (Win64) und über die Option types z. B. Double an Single oder Extended an Double. Wie W1071 (Ganzzahlen), W1072 (Gleitkomma) und W1066 (Extended an Double); der Compiler zeigt W1071 nur, wenn man es einschaltet. Gemeldet wird nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse, eigene Aliase und ganzzahlige Rechnungen daraus); Literale und ausdrückliche Umwandlungen bleiben still. Standardmäßig aus; mittlere Konfidenz. Korrekturen: ausdrücklich umwandeln; den Typ der Deklaration des Ziels vergrößern (einzelne Variable aus derselben Datei).

Entspricht der Compilermeldung `W1071`, `W1072`, `W1066`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `types` | string-list | `["Int64>Integer","NativeInt>Integer"]` | Gemeldete Paare Quelltyp>Zieltyp, z. B. Double>Single oder Extended>Double. |

Mit Treffer:

```pascal
Anzahl := Strom.Size;  // Anzahl: Integer
```

Richtig:

```pascal
Anzahl := Integer(Strom.Size);
```

<a id="typed-constant-modified"></a>
### typed-constant-modified

**Typisierte Konstante verändert** · Bug · Warnung · Gruppe Compiler vorab

Einer typisierten Konstante (const Zaehler: Integer = 0) wird etwas zugewiesen (wie W1017, auch einem Element oder Record-Feld davon), oder sie wird als var- oder out-Argument übergeben, auch an Inc, Dec, Include, Exclude, Delete, SetLength und ähnliche (wie W1016). Gemeint war meist eine Variable; übersetzbar ist das nur mit {$J+}. Gilt vor der Deklaration in derselben Datei {$J-} bzw. {$WRITEABLECONST OFF}, meldet Atlas einen Fehler (wie E2064 bzw. E2197). Dazu 0 als Wert einer Zeigerkonstante oder einer initialisierten Zeigervariable (wie W1013). Korrekturen: eine Konstante auf Unit-Ebene in eine Variable mit Initialwert umwandeln (der const-Abschnitt wird bei Bedarf geteilt; lokale typisierte Konstanten behalten ihren Wert zwischen Aufrufen und bekommen keine Korrektur); nil statt 0 schreiben.

Entspricht der Compilermeldung `W1016`, `W1017`, `W1013`, `E2064`, `E2197`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
const
  Zaehler: Integer = 0;
…
Inc(Zaehler);
```

Richtig:

```pascal
var
  Zaehler: Integer = 0;
…
Inc(Zaehler);
```

<a id="string-length-limit"></a>
### string-length-limit

**String-Grenze überschritten** · Bug · Warnung · Gruppe Compiler vorab

Ein String-Literal wird an ein Ziel vom Typ string[N] oder ShortString gekürzt: Zuweisung, typisierte Konstante oder initialisierte Variable, auch über eigene Aliase, string[Konstante] und Felder aus anderen Units (wie W1014). Vor Delphi 12 (delphiVersion unter 23) darf ein Literal in Anführungszeichen höchstens 255 Zeichen haben (wie E2056), und ein resourcestring höchstens 4096 Zeichen, mit + verbundene Literale eingerechnet (wie E2381); beides sind Fehler. Gezählt wird wie geschrieben, '' und #13 zählen als ein Zeichen. Korrekturen: das Ziel als string deklarieren (einzelne Variable oder typisierte Konstante derselben Datei; Record-Felder behalten ihre Größe); das Literal in Stücke zu 255 Zeichen teilen, verbunden mit +.

Entspricht der Compilermeldung `W1014`, `E2056`, `E2381`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
var Kennung: string[8];
…
Kennung := 'KUNDE-2026-0001';
```

Richtig:

```pascal
var Kennung: string;
…
Kennung := 'KUNDE-2026-0001';
```

<a id="dynamic-array-misuse"></a>
### dynamic-array-misuse

**New, Dispose oder SetLength falsch für dynamische Arrays** · Bug · Fehler · Gruppe Compiler vorab

New (wie E2255) oder Dispose (wie E2256) auf einem dynamischen Array, SetLength ohne Länge (wie E2246), New mit Länge auf einem Typ, der kein dynamisches Array ist (wie E2307), und New(TArrayTyp) ohne Länge (wie E2308). Häufig in altem Code, der von Zeigern auf dynamische Arrays umgestellt wurde. Die Regel meldet nur, wenn die Namensauflösung Variable bzw. Typ sicher kennt; Aliase werden verfolgt (TWerte = array of Double), TBytes und die übrigen dynamischen Arrays der RTL gelten auch ohne Index; offene Array-Parameter und Zeiger bleiben still. Korrekturen: Dispose(A) wird A := nil, New(A) wird SetLength(A, 1).

Entspricht der Compilermeldung `E2255`, `E2256`, `E2246`, `E2307`, `E2308`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
Dispose(Werte);
```

Richtig:

```pascal
Werte := nil;
```

<a id="local-routine-as-callback"></a>
### local-routine-as-callback

**Lokale Routine als Prozedurvariable** · Bug · Fehler · Gruppe Compiler vorab

Eine lokale (verschachtelte) Routine wird einer Variablen oder einem Parameter eines prozeduralen Typs ohne of object zugewiesen (wie E2094), oder eine typisierte Konstante einer Routine nimmt die Adresse einer lokalen Variablen (wie E2278). Gemeint ist meist eine anonyme Methode oder eine Routine der Unit. Die Regel meldet nur, wenn die Namensauflösung den Zieltyp sicher kennt; Methodenzeiger und Methodenreferenzen bleiben still, weil der Compiler sie mit anderen Codes meldet, ebenso @Routine (ein untypisierter Zeiger). Korrektur: die Routine als Routine der Unit vor die umgebende Routine verschieben, wenn sie nichts aus ihr nutzt (keine lokalen Namen weiter außen, keine Klassenmitglieder ohne Präfix).

Entspricht der Compilermeldung `E2094`, `E2278`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
procedure TListe.Sortieren;
  function Vergleich(A, B: Pointer): Integer;
  begin
    Result := 0;
  end;
begin
  FListe.Sort(Vergleich);
end;
```

Richtig:

```pascal
function Vergleich(A, B: Pointer): Integer;
begin
  Result := 0;
end;

procedure TListe.Sortieren;
begin
  FListe.Sort(Vergleich);
end;
```

<a id="hresult-integer-mix"></a>
### hresult-integer-mix

**Integer und HRESULT vertauscht** · Bug · Warnung · Gruppe Compiler vorab

Eine Klasse implementiert eine Interface-Methode mit HRESULT-Ergebnis über eine Methode mit Integer- (bzw. LongInt-) Ergebnis oder umgekehrt (wie X1008). Beide sind 32 Bit groß, deshalb fällt es nicht auf; die Bedeutung der Werte (S_FALSE als Erfolg) geht aber verloren; wichtig für COM- und OTA-Code. Zugeordnet wird über Name und Parametertypen samt Zuordnungen wie function IFoo.Bar = Baz; Interfaces samt ihren Vorfahren kommen aus der Datei bzw. dem Index. Stehen Varianten in bedingten Zweigen, meldet die Regel nur, wenn jede Variante abweicht. Korrektur: den Ergebnistyp in Deklaration und Implementierung an das Interface angleichen.

Entspricht der Compilermeldung `X1008`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
IExport = interface
  function Schreiben: HRESULT; stdcall;
end;
…
  function Schreiben: Integer; stdcall;
```

Richtig:

```pascal
IExport = interface
  function Schreiben: HRESULT; stdcall;
end;
…
  function Schreiben: HRESULT; stdcall;
```

<a id="invalid-var-argument"></a>
### invalid-var-argument

**Ungültiges Argument für einen var- oder out-Parameter** · Bug · Fehler · Gruppe Compiler vorab

Ein var- oder out-Parameter bekommt etwas, das keine Variable ist: ein String-Element für einen Zeichen-Parameter (wie E2354), eine Konstante, einen const-Parameter, eine Property oder ein Funktionsergebnis (wie E2197), eine Konstante für ein offenes Array (wie E2192), Slice (wie E2454) oder einen Ausdruck (wie E2036). Gemeldet nur für Routinen ohne Überladungen, deren Kopf aus der Datei oder dem Index bekannt ist; eingebaute Routinen wie Inc oder Move und untypisierte var-Parameter nehmen mehr an und bleiben still. Typisierte Konstanten zählen als Konstanten, außer mit {$J+}. Korrektur: eine lokale Variable vom Typ des Parameters übergeben, bei String-Elementen und Properties mit write mit Rückschreiben.

Entspricht der Compilermeldung `E2354`, `E2197`, `E2192`, `E2454`, `E2036`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
procedure Erhoehen(var Zeichen: Char);
…
Erhoehen(Zeile[1]);
```

Richtig:

```pascal
Zeichen := Zeile[1];
Erhoehen(Zeichen);
Zeile[1] := Zeichen;
```

<a id="condition-not-boolean"></a>
### condition-not-boolean

**Bedingung ist kein Boolean** · Bug · Fehler · Gruppe Compiler vorab

Die Bedingung von if, while, until oder eines bedingten Ausdrucks hat sicher einen Typ, der kein Boolean ist: Zahl, Zeiger, Klasse, Interface, String oder Zeichen (wie E2012). Anders als C verlangt Delphi einen Boolean. Gemeldet nur bei sicher bekanntem Typ; Boolean-Typen wie LongBool, Aufzählungen, Aliase und unbekannte Typen bleiben still. Korrektur: <> 0 (Alternative > 0), <> nil (Alternative Assigned), <> '' bzw. <> #0 ergänzen.

Entspricht der Compilermeldung `E2012`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
if Liste.Count then
  Verarbeiten;
```

Richtig:

```pascal
if Liste.Count > 0 then
  Verarbeiten;
```

<a id="for-in-not-enumerable"></a>
### for-in-not-enumerable

**for-in über einen Typ ohne Enumerator** · Bug · Fehler · Gruppe Compiler vorab

Eine for-in-Schleife läuft über einen Typ, der sich nicht aufzählen lässt: Zahl, Zeiger, Zeichen oder Boolean, oder eine Klasse, ein Record bzw. Interface ohne öffentliches GetEnumerator, auch nicht geerbt oder aus einem Helper (wie E2430); oder der Enumerator aus GetEnumerator hat kein öffentliches MoveNext bzw. Current (wie E2431). Strings, Arrays und Mengen gehen. Gemeldet nur, wenn der Typ und alle Vorfahren bekannt sind; generische und unbekannte Typen bleiben still. Keine Korrektur; hat der Typ Count, nennt die Meldung eine Schleife mit Index.

Entspricht der Compilermeldung `E2430`, `E2431`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
for F in Felder.Dataset do
```

Richtig:

```pascal
for F in Felder do
```

<a id="inherited-abstract-call"></a>
### inherited-abstract-call

**inherited ruft eine abstrakte Methode auf** · Bug · Fehler · Gruppe Compiler vorab

inherited mit ausdrücklichem Methodennamen, etwa inherited Zeichnen(C), obwohl die Methode im Vorfahren abstract ist (wie E2373). Ein bloßes inherited; übergeht der Compiler bei abstrakten Methoden still; das meldet die Regel nicht. Die Methode löst die Namensauflösung samt Überladungen auf; gemeldet wird nur, wenn jede passende Überladung abstrakt ist. Korrektur: den Aufruf entfernen, wenn er als eigene Anweisung in einem begin…end steht.

Entspricht der Compilermeldung `E2373`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
procedure TKreis.Zeichnen(C: TCanvas);
begin
  inherited Zeichnen(C);
  C.Ellipse(FRahmen);
end;
```

Richtig:

```pascal
procedure TKreis.Zeichnen(C: TCanvas);
begin
  C.Ellipse(FRahmen);
end;
```

<a id="override-only-inherited"></a>
### override-only-inherited

**override ruft nur inherited auf** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine überschreibende Methode, deren Rumpf nur die geerbte Methode aufruft: ein bloßes inherited;, inherited Name oder inherited Name(A, B) mit den eigenen Parametern in unveränderter Reihenfolge, in Funktionen nur Result := inherited Name(…). Sie tut nichts Eigenes und täuscht ein geändertes Verhalten vor. Still, wenn die Methode die Sichtbarkeit der geerbten ändert (protected zu public), ein Attribut, Standardwerte oder die Direktiven final, deprecated, experimental, platform, library oder reintroduce trägt, lokale Deklarationen, mehr als eine Anweisung, Kommentare oder bedingte Direktiven im Rumpf hat oder die überschriebene Methode unbekannt ist (Vorfahr nicht im Index; virtuelle Methoden von TObject gelten als public). Sicherheit hoch. Korrektur: Deklaration und Rumpf entfernen, samt XMLDoc-Kommentaren und der Leerzeile hinter dem Rumpf.

Mit Treffer:

```pascal
type
  TKundenForm = class(TForm)
  protected
    procedure Loaded; override;
  end;

procedure TKundenForm.Loaded;
begin
  inherited Loaded;
end;
```

Richtig:

```pascal
type
  TKundenForm = class(TForm)
  end;
```

<a id="inherited-without-ancestor"></a>
### inherited-without-ancestor

**inherited ohne Methode im Vorfahr** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein bloßes inherited; in einer Methode, die kein Vorfahr deklariert (neue Methode, kein override), tut nichts. Das deutet auf ein vergessenes override oder einen Tippfehler im Namen. Nicht gemeldet: Message-Handler (inherited ruft dort DefaultHandler), Klassen- und statische Methoden, Konstruktoren und Destruktoren, override und reintroduce, inherited in anonymen Methoden, Vorfahren mit einem gleichnamigen Mitglied (auch nicht virtuell) und unbekannte Vorfahren. Vorfahren aus anderen Units liefert der Symbolindex; Methoden von TObject gelten als bekannt, wenn System nicht im Index steht. Sicherheit hoch. Korrektur: inherited entfernen, wenn es als eigene Anweisung in einem begin…end steht.

Mit Treffer:

```pascal
procedure TImport.Vorbereiten;
begin
  inherited;
  FZeilen.Clear;
end;
```

Richtig:

```pascal
procedure TImport.Vorbereiten;
begin
  FZeilen.Clear;
end;
```

<a id="redundant-jump"></a>
### redundant-jump

**Überflüssiges Exit oder Continue** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein bloßes Exit; als letzte Anweisung einer Routine oder anonymen Methode, oder ein bloßes Continue; als letzte Anweisung eines Schleifenrumpfs (for, for-in, while, repeat), auch im letzten Zweig eines if am Ende (der then-Zweig nur ohne else; then Continue else … bewacht eine else-if-Kette). Der Sprung ändert nichts. Nicht gemeldet: Exit mit Wert, Sprünge in try…finally oder try…except (der Sprung löst den finally-Teil bewusst aus), in case, qualifizierte Namen wie System.Continue, Anweisungen mit goto-Marke und Rümpfe mit bedingten Direktiven. Sicherheit hoch. Korrektur: die Anweisung entfernen, wenn sie in einem begin…end oder direkt in repeat steht.

Mit Treffer:

```pascal
procedure TPuffer.Leeren;
begin
  FLaenge := 0;
  Exit;
end;
```

Richtig:

```pascal
procedure TPuffer.Leeren;
begin
  FLaenge := 0;
end;
```

<a id="generic-constraint-violated"></a>
### generic-constraint-violated

**Typargument verletzt eine Einschränkung** · Bug · Fehler · Gruppe Compiler vorab

Ein Typargument erfüllt die Einschränkung seines Typparameters nicht: class (wie E2511), record (wie E2512), constructor (wie E2513), ein Interface (wie E2514) oder eine Basisklasse (wie E2515). In Methoden eines generischen Typs dieser Datei meldet die Regel außerdem T.Create ohne constructor-Einschränkung (wie E2568) und Methodenaufrufe auf Werten eines Typparameters ganz ohne Einschränkung (wie E2571). Den generischen Typ löst die Namensauflösung samt Zahl der Typparameter auf, seine Einschränkungen stammen aus seiner Deklaration in der Datei oder im Symbolindex. Argumente, die selbst Typparameter sind, Aliase und Typen mit unvollständiger Vorfahrenkette meldet die Regel nicht. Korrektur für einen Typparameter dieser Datei, der allein in seiner Gruppe steht: die Einschränkung ergänzen (T: class, constructor bzw. T: class).

Entspricht der Compilermeldung `E2511`, `E2512`, `E2513`, `E2514`, `E2515`, `E2568`, `E2571`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
  TFabrik<T: class> = class
    function Neu: T;
  end;
…
  Result := T.Create;
```

Richtig:

```pascal
  TFabrik<T: class, constructor> = class
    function Neu: T;
  end;
…
  Result := T.Create;
```

<a id="unresolved-type"></a>
### unresolved-type

**Typ in einer Deklaration nicht gefunden** · Bug · Fehler · Gruppe Compiler vorab

Ein Typname in einer Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable, Typargument) ist nicht deklariert (wie E2003, beim Ziel eines Zeigertyps wie E2564) oder kein Typ (wie E2005). Ergänzt unresolved-identifier, das nur Anweisungen prüft. Dieselben Vorbedingungen wie bei unresolved-attribute: System im Symbolindex, alle Units aus uses bekannt, nicht in {$IF…}-Blöcken. Typparameter, Namen, die die Datei irgendwo als Typ deklariert (auch verschachtelt), und Namen, die der Index als verschachtelten Typ kennt (geerbte innere Typen), meldet die Regel nicht. Korrektur: die Unit, die den Typ (mit gleich vielen Typparametern) deklariert, in uses aufnehmen.

Entspricht der Compilermeldung `E2564`, `E2563`, `E2005`, `E2003`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
uses
  System.SysUtils;
type
  TKunden = TObjectList<TKunde>;
```

Richtig:

```pascal
uses
  System.SysUtils, System.Generics.Collections;
type
  TKunden = TObjectList<TKunde>;
```

<a id="class-reference-nonvirtual-constructor"></a>
### class-reference-nonvirtual-constructor

**Konstruktor über Klassenreferenz nicht virtuell** · Bug · Warnung · Gruppe Compiler vorab

Create über eine Klassenreferenz (class of TBasis), deren Konstruktor nicht virtual ist. Unter Win32 und Win64 übersetzt das ohne Meldung, erzeugt aber immer über den Konstruktor von TBasis: Felder, die Nachfahren in ihren eigenen Konstruktoren setzen, bleiben leer (wie E2391). Der Empfänger kann eine Variable, ein Feld, ein Parameter oder ein Funktionsergebnis vom Typ einer Klassenreferenz sein; den Konstruktor löst die Namensauflösung in der nächsten Klasse auf, die ihn deklariert, Überladungen nach Zahl der Argumente. Still, wenn eine passende Überladung virtual, dynamic, override oder abstract ist, wenn eine Deklaration in einem anderen Zweig der bedingten Übersetzung steht und wenn ein Typ nicht auflösbar ist. Korrektur, wenn der Konstruktor in dieser Datei steht: virtual an ihn und override an die gleichlautenden Konstruktoren der Nachfahren in dieser Datei.

Entspricht der Compilermeldung `E2391`.

Stufe B (Namensauflösung über Units).

Mit Treffer:

```pascal
type
  TPluginKlasse = class of TPlugin;
  TPlugin = class
    constructor Create;
  end;
...
  P := Klasse.Create;
```

Richtig:

```pascal
type
  TPluginKlasse = class of TPlugin;
  TPlugin = class
    constructor Create; virtual;
  end;
  TSpezial = class(TPlugin)
    constructor Create; override;
  end;
...
  P := Klasse.Create;
```

<a id="jump-outside-allowed-scope"></a>
### jump-outside-allowed-scope

**Break, Continue oder Exit an unzulässiger Stelle** · Bug · Fehler · Gruppe Compiler vorab

Break oder Continue außerhalb einer Schleife (wie E2097) bzw. Break, Continue oder Exit, die einen finally-Block verlassen (wie E2126). Delphi meldet beides erst beim Übersetzen; häufig nach dem Herausziehen eines Schleifenrumpfs in eine eigene Methode. Eine Schleife ganz im finally-Block darf Break und Continue verwenden. Routinen und anonyme Methoden beginnen neu: Ein Break in einer anonymen Methode gehört nicht zur Schleife um sie herum. Gemeldet werden nur einfache Aufrufe (nicht TMonitor.Exit(FLock)) und nicht, wenn die Datei eine Routine oder Variable dieses Namens deklariert. Korrektur außerhalb eines finally-Blocks: Break durch Exit ersetzen.

Entspricht der Compilermeldung `E2097`, `E2126`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
if Eintrag.Treffer then
  Break;
```

Richtig:

```pascal
if Eintrag.Treffer then
  Exit;
```

<a id="reraise-outside-handler"></a>
### reraise-outside-handler

**raise ohne Argument außerhalb eines Handlers** · Bug · Fehler · Gruppe Compiler vorab

raise; ohne Exception-Objekt ist nur in einem except-Block erlaubt (wie E2145); Delphi meldet es erst beim Übersetzen. Es passiert in einer lokalen Prozedur, die aus dem Handler gerufen wird, in einem finally-Block oder nach dem Verschieben von Code. Routinen und anonyme Methoden beginnen neu. Still bleibt die Regel in anonymen Methoden innerhalb eines except-Blocks und in Routinen, in denen der Parser einen Fehler meldet. Keine Korrektur: eine neue Exception auslösen (raise EImport.Create(…)) oder den Code in den Handler verschieben. raise E; im Handler meldet reraise-exception-object.

Entspricht der Compilermeldung `E2145`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
Protokoll.Fehler('Import abgebrochen');
raise;
```

Richtig:

```pascal
Protokoll.Fehler('Import abgebrochen');
raise EImportAbgebrochen.Create('Import abgebrochen');
```

<a id="label-misuse"></a>
### label-misuse

**Sprungmarke falsch verwendet** · Bug · Fehler · Gruppe Compiler vorab

Eine Marke ist doppelt gesetzt (wie E2073), deklariert und angesprungen, aber nie gesetzt (E2074), gesetzt oder angesprungen, ohne in der aktuellen Routine deklariert zu sein (E2093; ein goto auf eine nirgends deklarierte und nie gesetzte Marke meldet die Regel syntax als E2031), oder goto springt in einen try-Block hinein oder aus ihm heraus, auch zwischen try-Teil und except bzw. finally (E2127). Delphi meldet das erst beim Übersetzen. Marken gehören zu einer Routine bzw. zum Programmblock; eine lokale Prozedur kann keine Marke der umgebenden Routine anspringen. Doppelte Marken in bedingten Zweigen, die sich ausschließen, bleiben still, ebenso Routinen mit asm-Block, weil Marken im asm nicht im Syntaxbaum stehen. Keine Korrektur.

Entspricht der Compilermeldung `E2073`, `E2074`, `E2093`, `E2127`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
label Weiter;
begin
  try
    if Fertig then goto Weiter;
  finally
    Aufraeumen;
  end;
Weiter:
end;
```

Richtig:

```pascal
begin
  try
    if Fertig then Exit;
  finally
    Aufraeumen;
  end;
end;
```

<a id="for-variable-misuse"></a>
### for-variable-misuse

**Schleifenvariable verändert oder nicht lokal** · Bug · Fehler · Gruppe Compiler vorab

Der Variablen einer for-Schleife wird im Rumpf zugewiesen oder sie wird mit Inc/Dec verändert (wie E2081), sie wird als var- bzw. out-Parameter an eine Routine dieser Datei übergeben (wie W1015) oder sie ist keine einfache lokale Variable: Feld der eigenen Klasse, globale Variable der Unit oder lokale Variable der umgebenden Routine (wie E1019). Delphi meldet das erst beim Übersetzen. Parameter, unbekannte Namen und Schleifen in with-Anweisungen bleiben still, ebenso anonyme Methoden im Rumpf und Routinen mit Parserfehlern. Korrekturen: auf eine while-Schleife umstellen (nicht bei Continue im Rumpf) bzw. for var verwenden, wenn die Routine den Namen sonst nicht benutzt.

Entspricht der Compilermeldung `E2081`, `W1015`, `E1019`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
for I := 0 to Zeilen.Count - 1 do
begin
  if Zeilen[I] = '' then
    Inc(I);
end;
```

Richtig:

```pascal
I := 0;
while I <= Zeilen.Count - 1 do
begin
  if Zeilen[I] = '' then
    Inc(I);
  Inc(I);
end;
```

<a id="for-variable-after-loop"></a>
### for-variable-after-loop

**Schleifenvariable nach der Schleife gelesen** · Bug · Warnung · Gruppe Compiler vorab

Nach einer for-Schleife, die normal endet (ohne Break), ist die Schleifenvariable undefiniert. Die Regel meldet das erste Lesen der Variable auf einem Weg vom normalen Schleifenende, bevor ihr erneut zugewiesen wird (wie W1037). Geprüft werden nur einfache lokale Variablen der Routine; for var, Felder, globale Variablen, Lesen nur im Rumpf, Argumente von Routinen, die out-Parameter sein könnten, und Routinen mit unvollständigem Ablaufgraphen bleiben still. Korrektur: auf eine while-Schleife umstellen, deren Zähler danach einen festen Wert hat.

Entspricht der Compilermeldung `W1037`.

Stufe A (Parser genügt).

Mit Treffer:

```pascal
for I := 0 to High(Werte) do
  if Werte[I] = Gesucht then
    Break;
Gefunden := I <= High(Werte);
```

Richtig:

```pascal
I := 0;
while I <= High(Werte) do
begin
  if Werte[I] = Gesucht then
    Break;
  Inc(I);
end;
Gefunden := I <= High(Werte);
```

<a id="argument-count-mismatch"></a>
### argument-count-mismatch

**Falsche Anzahl Argumente** · Bug · Fehler · Gruppe Compiler vorab

Ein Aufruf übergibt mehr Argumente, als die Routine Parameter hat (wie E2034), oder weniger als Parameter ohne Standardwert (wie E2035), auch als Anweisung ohne Klammern. Geprüft wird nur, wenn der Name sicher genau eine Routine meint: Überladungen, varargs, Typumwandlungen, Variablen prozeduralen Typs, Bezeichner von System ohne Quelltext und Deklarationen in bedingten Zweigen bleiben beim Compiler (E2250). Eine Funktion mit zu vielen Argumenten meldet die Regel nur bei bekanntem, nicht prozeduralem Ergebnistyp. Korrektur: Signaturhilfe öffnen setzt die Schreibmarke in die Klammern und öffnet den Parameter-Hint (ergänzt () bei Bedarf).

Entspricht der Compilermeldung `E2034`, `E2035`.

Stufe T (braucht Ausdruckstypen; mit "group:compiler": {"typeLevel": "off"} abschaltbar).

Mit Treffer:

```pascal
Versenden(Kunde.Mail, 'Rechnung');
```

Richtig:

```pascal
Versenden(Kunde.Mail, 'Rechnung', Text);
```
