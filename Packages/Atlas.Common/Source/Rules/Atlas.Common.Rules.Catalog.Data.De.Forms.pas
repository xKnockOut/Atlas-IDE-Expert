unit Atlas.Common.Rules.Catalog.Data.De.Forms;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeForms: array[0..74] of string = (
    '{',
    '      "id": "form-field-without-object",',
    '      "name": "Formularfeld ohne Objekt",',
    '      "description": "Ein published-Komponentenfeld der Formularklasse hat kein Objekt in der .dfm/.fmx neben der Unit. Nach dem Laden bleibt das Feld nil. Felder außerhalb von published werden nicht ' +
    'geprüft."',
    '    },',
    '{',
    '      "id": "form-object-without-field",',
    '      "name": "Formularobjekt ohne Feld",',
    '      "description": "Ein Objekt der Formulardatei hat kein Feld in der Formularklasse. Geerbte Objekte, Objekte in inline-Frames, namenlose Komponenten und Collection-Einträge werden übergangen. Die ' +
    'Korrektur ergänzt das Feld."',
    '    },',
    '{',
    '      "id": "form-field-type-mismatch",',
    '      "name": "Feldtyp weicht vom Formularobjekt ab",',
    '      "description": "Der Typ des Felds weicht von der Klasse des Objekts in der Formulardatei ab. Ohne Quelltext der Klasse aus der Formulardatei wird nicht verglichen. Die Korrektur ändert den Feldt' +
    'yp."',
    '    },',
    '{',
    '      "id": "dfm-circular-datasource",',
    '      "name": "Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung",',
    '      "description": "MasterSource/DataSource-Verknüpfungen der Formulardatei bilden einen Kreis (tblA → dsB → tblB → dsA → tblA). Das Öffnen der Datasets läuft in eine Rekursion oder zeigt keine stim' +
    'migen Daten."',
    '    },',
    '{',
    '      "id": "dfm-master-without-fields",',
    '      "name": "Master-Detail ohne MasterFields",',
    '      "description": "Ein Dataset hat MasterSource, aber keine MasterFields. Das Detail wird nicht gefiltert und zeigt alle Datensätze."',
    '    },',
    '{',
    '      "id": "dfm-required-field-without-control",',
    '      "name": "Pflichtfeld ohne sichtbares Eingabe-Control",',
    '      "description": "Ein persistentes Feld mit Required = True ist an kein sichtbares datensensitives Control gebunden (ein Gitter ohne DataField zählt für alle Felder). Der Anwender kann es nicht fü' +
    'llen, Post schlägt fehl."',
    '    },',
    '{',
    '      "id": "dfm-control-field-type-mismatch",',
    '      "name": "Datensensitives Control passt nicht zum Feldtyp",',
    '      "description": "Das Control passt nicht zum persistenten Feld, z. B. TDBEdit an einem TBooleanField oder Blob-Feld, TDBImage an einem Feld ohne Grafik."',
    '    },',
    '{',
    '      "id": "dfm-duplicate-binding",',
    '      "name": "Zwei Controls an demselben Feld",',
    '      "description": "Zwei Eingabe-Controls nutzen dieselbe DataSource und dasselbe DataField. Meist ein Kopierfehler. Anzeige-Controls (TDBText, TDBImage) zählen nicht."',
    '    },',
    '{',
    '      "id": "dfm-property",',
    '      "name": "Komponenten-Property verletzt eine Eigenschaftsregel",',
    '      "description": "Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zähl' +
    'en mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt. Die Schnellkorrektur setzt den Wert in der Formulardatei (fix: auto auch m' +
    'it source.fixAll); der Befehl \"Eigenschaftsregeln anwenden\" korrigiert ein Formular, das Projekt oder die Gruppe mit Vorschau."',
    '    },',
    '{',
    '      "id": "foreign-form-control-access",',
    '      "name": "Zugriff auf Controls eines anderen Formulars",',
    '      "description": "Code greift über die globale Variable auf ein Feld eines Formulars oder Frames aus einer anderen Unit zu (Form2.Edit1.Text). Das koppelt die Units eng; besser eine Methode oder P' +
    'roperty des Formulars nutzen."',
    '    },',
    '{',
    '      "id": "form-resource-missing",',
    '      "name": "Formular-Unit ohne {$R *.dfm}",',
    '      "description": "Neben der Unit liegt eine .dfm bzw. .fmx, die Unit deklariert die Klasse ihres Wurzelobjekts, aber keine {$R …}-Direktive bindet eine Formulardatei ein: Beim Erzeugen des Formula' +
    'rs folgt EResNotFound. Umgekehrt meldet die Regel ein {$R *.dfm} bzw. {$R Name.dfm}, dessen Datei neben der Unit fehlt (der Compiler bricht mit F1026 ab). Eine Direktive in einem beliebigen Zweig der ' +
    'bedingten Übersetzung zählt als eingebunden. Still bleibt die Regel, wenn die Klasse der Formulardatei nicht in der Unit steht und wenn sie keine Dateien neben der Unit sieht. Korrektur: {$R *.dfm} (b' +
    'zw. {$R *.fmx}) nach implementation einfügen."',
    '    },',
    '{',
    '      "id": "form-autocreate-and-manual",',
    '      "name": "Formular automatisch und zusätzlich von Hand erzeugt",',
    '      "description": "Die .dpr erzeugt ein Formular mit Application.CreateForm, der Code weist derselben globalen Variablen zusätzlich TfrmX.Create(…) zu. Es gibt dann zwei Instanzen, die erste bleibt' +
    ' unsichtbar im Speicher. Die automatisch erzeugten Formulare kommen aus der .dpr des Projekts, zu dem die Unit gehört; kann die Regel die .dpr lesen, muss die Klasse zum CreateForm-Aufruf passen. Stil' +
    'l bleibt sie, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil) oder vorher freigibt (Free, FreeAndNil, Release), bei lokalen Namen und gleichnamigen Feldern der eigenen Klasse und bei' +
    ' Units ohne Projekt. Sicherheit hoch. Korrektur: die Zeile mit Application.CreateForm aus der .dpr entfernen (das Formular erzeugt dann nur noch der Code)."',
    '    },',
    '{',
    '      "id": "inherited-form-handler-without-inherited",',
    '      "name": "Ereignis-Handler im geerbten Formular ohne inherited",',
    '      "description": "Bei Formularvererbung belegt ein Vorfahr-Formular dasselbe Ereignis derselben Komponente mit einem gleichnamigen Handler, der Handler im Nachfahren ruft inherited aber nicht (meh' +
    'r) auf. Die IDE erzeugt inherited; beim Anlegen; wird es gelöscht, fällt die Logik des Vorfahren still weg. Die Formulardatei des Vorfahren kommt aus dem Index (Datei der Klasse) bzw. aus den Units de' +
    'r uses-Liste neben der Unit; die Kette folgt geerbten Formularen bis zum ersten Formular mit object. Handler mit anderem Namen gelten als bewusster Ersatz. Still ohne Formulardatei des Vorfahren. Sich' +
    'erheit hoch. Korrektur: inherited; am Anfang einfügen."',
    '    },',
    '{',
    '      "id": "self-free-in-event-handler",',
    '      "name": "Formular gibt sich im eigenen Ereignis frei",',
    '      "description": "Free, Destroy, DisposeOf oder FreeAndNil auf Self bzw. auf die globale Variable der eigenen Formularklasse als Anweisung in einem Ereignis-Handler des Formulars oder eines seiner' +
    ' Controls. Nach der Rückkehr greift die VCL noch auf das Objekt zu: Zugriffsverletzung. Richtig ist Release oder Action := caFree in OnClose. Ereignis-Handler sind die Methoden aus der Formulardatei u' +
    'nd Methoden mit einem Parameter Sender: TObject; ein Formular ist die Wurzelklasse der Formulardatei mit ClientWidth bzw. ClientHeight oder eine direkt von TForm bzw. TCustomForm abgeleitete Klasse (R' +
    'ahmen und Datenmodule haben kein Release). Anweisungen in anonymen Methoden und with-Blöcken zählen nicht. Still ohne Formulardatei. Sicherheit hoch. Korrektur: Free durch Release ersetzen, in OnClose' +
    ' (var Action: TCloseAction) durch Action := caFree."',
    '    },',
    '{',
    '      "id": "dfm-reference-unit-missing",',
    '      "name": "Formulardatei verweist auf ein Modul, dessen Unit nicht in den uses steht",',
    '      "description": "Eine Property der Formulardatei zeigt auf eine Komponente eines anderen Formulars, Rahmens oder Datenmoduls (Connection = Form1.Connection), dessen Unit aber weder im interface- ' +
    'noch im implementation-uses steht. Beim Öffnen des Formulars öffnet die IDE nur die Module aus den uses mit; sonst bleibt der Verweis leer und geht beim Speichern verloren. Zur Laufzeit löst die VCL d' +
    'en Verweis nur auf, solange ein Modul dieses Namens existiert. Das Modul ist der Name der Wurzelkomponente (Form1, nicht TForm1). Seine Unit kommt aus der .dpr des Projekts (Unit1 in ''Unit1.pas'' {Form' +
    '1}, Sicherheit hoch), sonst aus dem Index: globale Variable dieses Namens im interface einer Unit, die ihren Typ als Klasse deklariert (Sicherheit mittel). Still bleibt die Regel bei Verweisen auf das' +
    ' eigene Formular, auf eigene Komponenten (eingebettete Rahmen wie Frame11.Button1) und auf Module, deren Unit weder .dpr noch Index kennen. Gemeldet wird am Feld der Komponente, die den Verweis hält, ' +
    'sonst an der Formularklasse; die Zeile der Formulardatei steht als weitere Stelle dabei. Korrektur: die Unit ins implementation-uses aufnehmen, wie es die IDE anbietet."',
    '    }');

implementation

end.
