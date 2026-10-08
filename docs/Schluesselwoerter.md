# Hover über Schlüsselwörtern und Direktiven

Der Hover erklärt seltene Sprachelemente mit einem Kurztext und verlinkt die DocWiki passend zur Delphi-Version des Projekts (#187). Gepflegt wird die Tabelle in `BDLsp.Common.Lsp.KeywordReference`. Ein Test prüft, dass jedes reservierte Wort des Lexers einen Eintrag hat oder auf der Liste der alltäglichen Wörter steht.

Der Hover erscheint nur, wenn an der Stelle kein Symbol gleichen Namens bekannt ist.

| Element | Art | Kurztext |
|---|---|---|
| `reintroduce` | Direktive | Verdeckt eine virtuelle Methode des Vorfahren bewusst, ohne sie zu überschreiben; unterdrückt die Warnung W1010. |
| `overload` | Direktive | Erlaubt mehrere Routinen gleichen Namens mit unterschiedlichen Parametern. |
| `override` | Direktive | Überschreibt eine virtuelle oder dynamische Methode des Vorfahren. |
| `virtual` | Direktive | Methode kann in Nachfahren überschrieben werden (Aufruf über die VMT). |
| `dynamic` | Direktive | Wie virtual, aber platzsparender und langsamer (Aufruf über die DMT). |
| `abstract` | Direktive | Methode ohne Implementierung; Nachfahren müssen sie überschreiben. |
| `final` | Direktive | Methode darf nicht weiter überschrieben, Klasse nicht abgeleitet werden. |
| `static` | Direktive | Klassenmethode ohne Self; nicht virtuell. |
| `message` | Direktive | Message-Handler: Methode wird für die angegebene Windows-Nachricht aufgerufen. |
| `inline` | reserviertes Wort | Bittet den Compiler, die Routine an der Aufrufstelle einzusetzen. |
| `forward` | Direktive | Vorwärtsdeklaration einer Routine, deren Rumpf später folgt. |
| `external` | Direktive | Routine aus einer DLL oder Objektdatei. |
| `assembler` | Direktive | Routine in Assembler (veraltet, nur zur Kompatibilität). |
| `varargs` | Direktive | Variable Parameterliste für externe C-Routinen. |
| `noreturn` | Direktive | Routine kehrt nicht zurück (z. B. nach raise). |
| `delayed` | Direktive | DLL wird erst beim ersten Aufruf geladen. |
| `cdecl` | Direktive | Aufrufkonvention von C: Parameter von rechts nach links, Aufrufer räumt den Stack. |
| `stdcall` | Direktive | Aufrufkonvention der Windows-API. |
| `safecall` | Direktive | Aufrufkonvention für COM: Ausnahmen werden zu HResult. |
| `register` | Direktive | Standard-Aufrufkonvention von Delphi (Parameter in Registern). |
| `pascal` | Direktive | Ältere Aufrufkonvention: Parameter von links nach rechts. |
| `winapi` | Direktive | Aufrufkonvention der Plattform-API (stdcall unter Windows). |
| `dispid` | Direktive | Nummer eines Mitglieds in einer Dispatch-Schnittstelle (Automation). |
| `deprecated` | Direktive | Verwendung erzeugt eine Warnung; optional mit Hinweistext. |
| `platform` | Direktive | Nur auf bestimmten Plattformen verfügbar; Verwendung erzeugt eine Warnung. |
| `experimental` | Direktive | Noch nicht stabil; Verwendung erzeugt eine Warnung. |
| `library` | reserviertes Wort | Kopf eines DLL-Projekts; als Hinweisdirektive: nur in dieser Bibliothek. |
| `strict private` | Sichtbarkeit | Nur innerhalb der Klasse sichtbar, auch nicht für andere Klassen derselben Unit. |
| `strict protected` | Sichtbarkeit | Nur in der Klasse und ihren Nachfahren sichtbar, nicht für andere Klassen derselben Unit. |
| `protected` | Sichtbarkeit | Sichtbar in der Klasse, ihren Nachfahren und der eigenen Unit. |
| `public` | Sichtbarkeit | Überall sichtbar. |
| `published` | Sichtbarkeit | Überall sichtbar, mit RTTI für den Objektinspektor und das Streaming (.dfm). |
| `automated` | Sichtbarkeit | Veraltet: wie public, mit Automation-Typinformationen. |
| `class var` | Deklaration | Klassenfeld: ein Wert für alle Instanzen der Klasse. |
| `sealed` | Direktive | Von der Klasse darf nicht abgeleitet werden. |
| `helper` | Direktive | Class Helper bzw. Record Helper: erweitert einen Typ um Methoden. |
| `dispinterface` | reserviertes Wort | Dispatch-Schnittstelle für Automation (Aufruf über IDispatch). |
| `object` | reserviertes Wort | Veralteter Objekttyp (Turbo Pascal); heute class bzw. record verwenden. |
| `packed` | reserviertes Wort | Felder ohne Ausrichtungslücken ablegen. |
| `property` | reserviertes Wort | Eigenschaft mit Lese- und Schreibzugriff über Felder oder Methoden. |
| `implements` | Direktive | Delegiert die Implementierung einer Schnittstelle an eine Property. |
| `stored` | Direktive | Ob der Wert der Property in der .dfm gespeichert wird (Boolean oder Funktion). |
| `default` | Direktive | Standardwert einer Property (wird dann nicht gespeichert) bzw. Standard-Array-Property. |
| `nodefault` | Direktive | Hebt einen geerbten Standardwert einer Property auf. |
| `index` | Direktive | Index, den mehrere Properties an dieselbe Zugriffsmethode übergeben. |
| `readonly` | Direktive | Dispatch-Property nur lesbar. |
| `writeonly` | Direktive | Dispatch-Property nur schreibbar. |
| `absolute` | Direktive | Variable liegt an derselben Adresse wie eine andere Variable. |
| `threadvar` | reserviertes Wort | Globale Variable mit eigenem Wert je Thread. |
| `resourcestring` | reserviertes Wort | Übersetzbarer String, der als Ressource abgelegt wird. |
| `out` | Direktive | Ausgabeparameter: Der Eingangswert wird verworfen. |
| `with` | reserviertes Wort | Macht die Mitglieder eines Objekts ohne Präfix zugänglich; erschwert das Lesen. |
| `goto` | reserviertes Wort | Sprung zu einer Marke (label). |
| `label` | reserviertes Wort | Deklariert Sprungmarken für goto. |
| `inherited` | reserviertes Wort | Ruft die gleichnamige Methode des Vorfahren auf. |
| `asm` | reserviertes Wort | Block mit Inline-Assembler. |
| `exports` | reserviertes Wort | Routinen, die eine DLL nach außen anbietet. |
| `file` | reserviertes Wort | Dateityp (file of …) für typisierte und untypisierte Dateien. |
| `initialization` | reserviertes Wort | Code, der beim Laden der Unit ausgeführt wird. |
| `finalization` | reserviertes Wort | Code, der beim Entladen der Unit ausgeführt wird. |
| `constructor` | reserviertes Wort | Methode, die eine Instanz anlegt und initialisiert. |
| `destructor` | reserviertes Wort | Methode, die eine Instanz freigibt; Destroy wird über Free aufgerufen. |
| `shl` | reserviertes Wort | Bits nach links schieben. |
| `shr` | reserviertes Wort | Bits nach rechts schieben. |
| `operator` | Direktive | Überladener Operator eines Records (class operator). |
| `if … then … else` | Ausdruck | Bedingungsausdruck: X := if A then B else C. (ab Delphi 13) |
| `is not` | Operator | Negierter Typtest: X is not TFoo. (ab Delphi 13) |
| `not in` | Operator | Negierter Mengentest: X not in [A, B]. (ab Delphi 13) |

Ohne Hover, weil alltäglich: `and`, `array`, `as`, `begin`, `case`, `class`, `const`, `div`, `do`, `downto`, `else`, `end`, `except`, `finally`, `for`, `function`, `if`, `implementation`, `in`, `interface`, `is`, `mod`, `nil`, `not`, `of`, `or`, `procedure`, `program`, `raise`, `record`, `repeat`, `set`, `string`, `then`, `to`, `try`, `type`, `unit`, `until`, `uses`, `var`, `while`, `xor`, `private`.
