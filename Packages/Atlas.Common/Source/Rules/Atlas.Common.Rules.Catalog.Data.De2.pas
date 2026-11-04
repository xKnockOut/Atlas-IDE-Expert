unit Atlas.Common.Rules.Catalog.Data.De2;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDe2: array[0..956] of string = (
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "ota-notifier-not-removed",',
    '      "name": "IDE-Notifier ohne RemoveNotifier",',
    '      "description": "AddNotifier an IOTAServices, IOTAEditorServices, IOTAModule usw. (oder ein anderes Paar aus registerPairs), dessen Index nie an RemoveNotifier geht: Der Aufruf steht als Anweisun' +
    'g ohne Zuweisung, oder die Variable, der er zugewiesen wird, erhält in der Unit kein RemoveNotifier (in finalization, im Destruktor oder in Destroyed). Die IDE ruft den Notifier dann nach dem Entladen' +
    ' des Packages in fremdem Speicher auf. Register…-Aufrufe in der Prozedur Register sind ausgenommen: Diese Wizards entfernt die IDE selbst. Sicherheit mittel. Korrektur in Methoden: Index in ein Feld l' +
    'egen (FNotifierIndex im private-Abschnitt) und RemoveNotifier im Destruktor ergänzen, der bei Bedarf angelegt wird; in Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in finalization. ' +
    'Keine Korrektur, wenn der Empfänger ein Parameter oder eine lokale Variable ist.",',
    '      "options": [',
    '        {',
    '          "name": "registerPairs",',
    '          "description": "Paare der Open Tools API als [{\"open\": \"AddNotifier\", \"close\": \"RemoveNotifier\"}]; ersetzt die Vorgabe."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "dunitx-test-without-assert",',
    '      "name": "DUnitX-Test ohne Assert",',
    '      "description": "Eine [Test]- oder [TestCase]-Methode, die keine Prüfung aufruft, weder selbst noch über ihre lokalen Routinen, Methoden derselben Klasse, Routinen der Unit oder freie Routinen an' +
    'derer Units, die der Symbolindex kennt (AssertTextPair aus einer gemeinsamen Testunit): Sie ist immer grün. Als Prüfung zählen Aufrufe nach assertPatterns (Vorgabe Assert.*, WillRaise*, Check*), Syste' +
    'm.Assert und Aufrufe an Klassen mit Assert im Namen (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still. Sicherheit hoch. Korrekturen: Assert.Pass als Platzhalter einfügen oder zu' +
    'r Methode springen.",',
    '      "options": [',
    '        {',
    '          "name": "assertPatterns",',
    '          "description": "Aufrufe, die als Prüfung zählen, als Muster mit * und ?; ersetzt die Vorgabe."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "event-call-without-assigned",',
    '      "name": "Ereignis ohne Assigned-Prüfung aufgerufen",',
    '      "description": "FOnChange(Self) oder OnChange(Self) wird in einer Methode der Klasse aufgerufen, ohne dass Assigned(FOnChange) oder FOnChange <> nil den Aufruf schützt: Ohne Handler folgt eine Z' +
    'ugriffsverletzung. Ereignisse sind Felder und Properties der Klasse mit Methodenzeiger- oder Referenztyp (procedure … of object, reference to …, TNotifyEvent, TProc/TFunc, Typen auf Event, prozedurale' +
    ' Typen der Unit oder des Index). Schutz: der then-Zweig einer Bedingung mit Assigned (auch while), der else-Zweig von not Assigned, \"Assigned(F) and\" vor dem Aufruf oder \"if not Assigned(F) then Ex' +
    'it/raise\" davor, auch über einen Merker oder eine Methode der Klasse ohne Parameter, deren Result Assigned(F) enthält. Still bleiben Felder, die ein Konstruktor mit einem Wert belegt (eingereichte Ab' +
    'hängigkeiten wie FReadText := AReadText), Properties darauf und gleichnamige lokale Namen. Sicherheit hoch. Korrektur: den Aufruf in \"if Assigned(F) then\" einschließen, wenn er als eigene Anweisung ' +
    'in einem Block steht."',
    '    },',
    '    {',
    '      "id": "owned-item-freed",',
    '      "name": "Element einer besitzenden Liste zusätzlich freigegeben",',
    '      "description": "Ein Element einer TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True) oder eines TObjectDictionary mit doOwnsValues wird mit Free, FreeAndNil, Destroy oder DisposeOf freigegeb' +
    'en, direkt (Liste[I].Free, Liste.Items[I].Free) oder über eine Variable aus Liste[I], Liste.First/Last oder einer for-in-Schleife über die Liste bzw. Dictionary.Values. Die Liste gibt das Element selb' +
    'st frei: bei Delete, Remove, Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben, also doppelt. Besitzend ist eine Liste, wenn die Unit sie so erzeugt (TObjectList ohne False, TObjectDic' +
    'tionary mit doOwnsValues) oder ohne Erzeugung als TObjectList deklariert, und kein OwnsObjects := False folgt. Extract in derselben Routine lässt die Regel schweigen. Sicherheit hoch. Korrekturen: Fre' +
    'e entfernen (die ganze Schleife, wenn sie nur freigibt), Delete bzw. Remove statt Free, Extract statt Remove."',
    '    },',
    '    {',
    '      "id": "create-without-assignment",',
    '      "name": "Objekt erzeugt und sofort verloren",',
    '      "description": "TStringList.Create; als eigene Anweisung: Das Objekt wird erzeugt, aber nirgends gespeichert und nie freigegeben (Speicherleck). Still bleiben Komponenten mit Owner (erstes Argum' +
    'ent Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit einem Argument ungleich nil), Threads (geben sich mit FreeOnTerminate selbst frei), Records, unbekannte Klassen mit Argumenten' +
    ' und Klassen aus selfRegistering. Sicherheit hoch. Korrektur: Zuweisung an eine neue lokale Variable, die folgenden Anweisungen des Blocks in try/finally mit Free.",',
    '      "options": [',
    '        {',
    '          "name": "selfRegistering",',
    '          "description": "Klassen, die sich im Konstruktor selbst registrieren, als Muster mit * und ?; Create als Anweisung bleibt für sie still."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "raw-memory-leak",',
    '      "name": "GetMem oder New ohne Freigabe",',
    '      "description": "Eine lokale Variable erhält Speicher über GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, die Routine gibt ihn aber nie mit FreeMem, FreeMemory, Dispose, StrD' +
    'ispose oder ReallocMem(P, 0) frei, und der Zeiger verlässt die Routine nicht: weder zurückgegeben (Result, Exit) noch einer anderen Variablen oder einem Feld zugewiesen, nicht über seine Adresse (@P) ' +
    'weitergegeben, keiner Methode übergeben, die ihn behält (Add, Insert, Push …), nicht von einer anonymen Methode eingefangen und nicht in einer lokalen Routine benutzt. Zum Lesen oder Füllen weitergebe' +
    'n (Pruefsumme(P, N), Strom.ReadBuffer(P^, N)) ist erlaubt; eine Routine mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen gilt als Freigabe. Eine Freigabe ohne try/finally meldet pair-wi' +
    'thout-finally. Konfidenz mittel. Schnellkorrektur: die folgenden Anweisungen des Blocks in try … finally mit der passenden Freigabe einschließen."',
    '    },',
    '    {',
    '      "id": "stringlist-objects-leak",',
    '      "name": "Objekte in einer TStringList ohne Besitz",',
    '      "description": "AddObject oder InsertObject legt ein neu erzeugtes Objekt (T.Create(…) direkt oder eine so erzeugte lokale Variable, die sonst nur gelesen wird) in eine TStringList (oder THashed' +
    'StringList), die die Unit ohne OwnsObjects erzeugt, oder in die Items eines Felds vom Typ TListBox, TComboBox, TCheckListBox, TComboBoxEx oder TColorListBox; niemand gibt diese Objekte frei. Besitzend' +
    ' ist eine Liste mit TStringList.Create(True) oder OwnsObjects := True. Still, wenn eine Routine der Unit Liste.Objects[…] liest und etwas freigibt, wenn die Liste weitergegeben wird (ObjekteFreigeben(' +
    'Liste), anderswo zugewiesen), wenn das Objekt einen Owner hat (Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit Argument) und bei Listen, die nicht in der Unit erzeugt werden. Kon' +
    'fidenz mittel. Schnellkorrektur: TStringList.Create(True) (auch statt Create(False)), bei anderen Konstruktoren OwnsObjects := True nach der Erzeugung; für Items von Steuerelementen keine."',
    '    },',
    '    {',
    '      "id": "message-handler-without-inherited",',
    '      "name": "Message-Handler ohne inherited",',
    '      "description": "Eine Methode mit message WM_… oder CM_… ruft weder inherited noch DefaultHandler (bzw. DefWindowProc, CallWindowProc) auf. Die Standardbehandlung der VCL bzw. von Windows fällt w' +
    'eg: kein Neuausrichten bei WM_SIZE, kein Schließen bei WM_CLOSE, kein Zeichnen bei WM_PAINT. Die Meldung nennt für gängige Nachrichten die Folge. Still bleiben Klassen ohne Vorfahr, Nachrichten aus sw' +
    'allow (Vorgabe WM_ERASEBKGND) und Handler, die Msg.Result selbst setzen (bewusste Antwort wie MA_NOACTIVATE). Sicherheit mittel. Korrektur: inherited; am Anfang einfügen.",',
    '      "options": [',
    '        {',
    '          "name": "swallow",',
    '          "description": "Nachrichten, die ohne inherited behandelt werden dürfen; ersetzt die Vorgabe."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "string-index-base",',
    '      "name": "String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen",',
    '      "description": "Die klassischen String-Routinen zählen ab 1: Copy(S, 0, N) und Insert(T, S, 0) wirken nur zufällig wie 1, Delete(S, 0, N) löscht nichts. Der String muss bekannt sein: deklarierte' +
    'r Typ in der Datei, Literal oder .Text/.Caption; dynamische Arrays (ab 0) bleiben still. Pos, PosEx und AnsiPos liefern 0 bei keinem Treffer: Pos(…) > -1, >= 0 und <> -1 sind immer wahr, = -1 und < 0 ' +
    'nie. Umgekehrt übersieht S.IndexOf(…) > 0 bzw. >= 1 den Treffer am Anfang, < 1 bzw. <= 0 zählt ihn als nicht gefunden (Sicherheit mittel; LastIndexOf bleibt still, dort heißt > 0 meist „nicht am Anfan' +
    'g“). Sicherheit hoch für Delete und Pos. Korrektur: Startwert 1 bzw. der richtige Vergleich (> 0, = 0, >= 0, < 0)."',
    '    },',
    '    {',
    '      "id": "delimited-text-without-strict",',
    '      "name": "DelimitedText ohne StrictDelimiter",',
    '      "description": "Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass StrictDelimiter gesetzt wird: DelimitedText trennt dann auch an Leerzeichen, ''Max Muster;Berlin' +
    ''' ergibt drei statt zwei Einträge. Bei Feldern zählt StrictDelimiter in der ganzen Unit (oft im Konstruktor); StrictDelimiter := False ist bewusst und bleibt still, ebenso DelimitedText ohne eigenen D' +
    'elimiter. Sicherheit hoch. Korrektur: StrictDelimiter := True; vor der Zuweisung einfügen."',
    '    },',
    '    {',
    '      "id": "self-as-interface-in-constructor",',
    '      "name": "Self während der Konstruktion als Interface weitergegeben",',
    '      "description": "Self wird als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann. Gemeldet werden nur zwei echte Fehlerfälle: (1) Eine Klasse mit eigener Refere' +
    'nzzählung (ein _Release in der Klassenkette gibt das Objekt frei, keine Klasse überschreibt NewInstance, die Kette ist bis TObject bekannt) gibt Self im Konstruktor oder in AfterConstruction als Inter' +
    'face weiter: Der Zähler steigt von 0 auf 1 und fällt wieder auf 0, das Objekt wird freigegeben, bevor die Konstruktion endet. (2) Ein Nachfahr von TInterfacedObject gibt Self in AfterConstruction nach' +
    ' inherited als Interface weiter: inherited AfterConstruction hat den Schutzzähler aus NewInstance schon abgebaut. Im Konstruktor eines TInterfacedObject-Nachfahren ist Self geschützt, die Regel bleibt' +
    ' still. Als Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Sicherheit hoch. Kor' +
    'rektur in Fall 2: die Anweisung vor inherited verschieben."',
    '    },',
    '    {',
    '      "id": "null-compare",',
    '      "name": "Vergleich mit Null statt VarIsNull oder IsNull",',
    '      "description": "X = Null bzw. X <> Null vergleicht einen Variant mit Null. Das Ergebnis hängt von der globalen Einstellung System.Variants.NullEqualityRule ab: Mit der Vorgabe ncrLoose vergleich' +
    't er wie erwartet, mit ncrStrict ist er nie wahr, mit ncrError löst er eine Exception aus. Eine Bibliothek, ein Testrahmen oder ein anderer Teil des Projekts kann die Einstellung ändern. VarIsNull(X) ' +
    'und Feld.IsNull prüfen unabhängig davon. Gemeldet wird nur, wo der Vergleich für sich steht (Bedingung, Argument, Zuweisung); not X = Null bindet als (not X) = Null und bekommt keine Korrektur. Sicher' +
    'heit hoch. Korrektur: Feld.IsNull bei X.Value auf FieldByName, FindField, Fields[…], ParamByName, Params[…] oder einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not davor."',
    '    },',
    '    {',
    '      "id": "unchecked-enum-cast",',
    '      "name": "Zahl ungeprüft in Aufzählung umgewandelt",',
    '      "description": "TStatus(N) mit einem Aufzählungstyp aus der Datei oder dem Index, wenn N aus einem Aufruf der Option sources stammt (FieldByName, ReadInteger, AsInteger, StrToInt): direkt im Arg' +
    'ument oder über eine Variable, die zwischen Zuweisung und Umwandlung nicht gelesen (geprüft) wird. Ein Wert außerhalb des Bereichs ergibt einen ungültigen Aufzählungswert, der in case durchfällt. Ensu' +
    'reRange, Min oder Max im Argument gelten als Prüfung; Konstanten, Rechnungen und unbekannte Typen bleiben still. Bei Aufzählungen mit eigenen Ordinalwerten nennt die Meldung den Bereich als Ord(Low(T)' +
    ')..Ord(High(T)). Sicherheit mittel. Korrektur bei direkter Quelle in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise EConvertError davor, System.Math in uses.",',
    '      "options": [',
    '        {',
    '          "name": "sources",',
    '          "description": "Aufrufe, deren Ergebnis als ungeprüft gilt."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "createprocess-readonly-commandline",',
    '      "name": "CreateProcess mit unveränderlicher Befehlszeile",',
    '      "description": "CreateProcess (CreateProcessW) und CreateProcessAsUser schreiben in den Puffer von lpCommandLine. Ein PChar auf Speicher, der nicht beschreibbar ist, führt zu einer Zugriffsverle' +
    'tzung. Gemeldet wird PChar(…)/PWideChar(…) auf: ein String-Literal oder eine Konstante; eine Verkettung aus genau einem Literal und einem Wert (ist der Wert leer, liefert die RTL das Literal selbst); ' +
    'eine lokale String-Variable, deren letzte Zuweisung vor dem Aufruf eines davon ist, ohne UniqueString danach; einen String-Parameter (Sicherheit mittel, der Aufrufer kann ein Literal übergeben). Funkt' +
    'ionsergebnisse wie Format und Verkettungen aus mehreren Teilen sind beschreibbare Heap-Strings und bleiben still, ebenso CreateProcessA, das die Befehlszeile selbst kopiert. Korrektur: Befehlszeile in' +
    ' eine lokale Variable kopieren und UniqueString aufrufen; bei einer Variablen UniqueString vor der Anweisung. In Schleifenbedingungen keine Korrektur."',
    '    },',
    '    {',
    '      "id": "form-access-before-create",',
    '      "name": "Zugriff auf ein Formular, das noch nicht erzeugt ist",',
    '      "description": "Der Konstruktor, AfterConstruction oder der OnCreate-Handler eines automatisch erzeugten Formulars bzw. Datenmoduls benutzt die globale Variable eines anderen Formulars, das die ' +
    '.dpr erst danach mit Application.CreateForm erzeugt. Die Variable ist dort noch nil. Die Reihenfolge stammt aus der .dpr des Projekts, zu dem die Unit gehört; der OnCreate-Handler aus der Formulardate' +
    'i (ohne Eintrag FormCreate bzw. DataModuleCreate). Still, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil), selbst zuweist, mit CreateForm erzeugt oder einen gleichnamigen lokalen Nam' +
    'en deklariert, und bei Formularen, die nicht automatisch erzeugt werden. Jede Variable wird je Routine einmal gemeldet. Sicherheit mittel. Keine Korrektur: die Reihenfolge in der .dpr ändern oder den ' +
    'Zugriff nach OnShow verlegen."',
    '    },',
    '    {',
    '      "id": "except-handler-order",',
    '      "name": "Allgemeiner Exception-Handler vor speziellem",',
    '      "description": "In einem try..except mit mehreren on-Handlern gewinnt der erste passende. Ein Handler für eine Klasse, die ein früherer Handler schon fängt, wird nie erreicht: Sein Code ist tot ' +
    'und die Sonderbehandlung läuft nie. Gemeldet, wenn ein früherer Handler dieselbe Klasse, einen Vorfahren davon, Exception (deckt jede Exception-Klasse ab) oder TObject nennt. Vorfahren kommen aus der ' +
    'Unit, dem Projektindex und einer Tabelle bekannter RTL-, VCL- und FireDAC-Exceptions (etwa EStreamError > EFOpenError, EIntError > ERangeError); unbekannte Klassen werden nur mit Exception und TObject' +
    ' verglichen. Korrektur: den speziellen Handler vor den allgemeinen verschieben (nur, wenn beide Handler auf eigenen Zeilen stehen). Ein doppelter Handler für dieselbe Klasse wird ohne Korrektur gemeld' +
    'et."',
    '    },',
    '    {',
    '      "id": "reraise-exception-object",',
    '      "name": "raise E statt raise im Handler",',
    '      "description": "raise E; in einem Handler on E: … löst das gefangene Exception-Objekt als neues raise aus. Die RTL gibt das Objekt nicht doppelt frei, aber die Ausnahme beginnt jetzt im Handler:' +
    ' ExceptAddr und die Aufrufliste von Werkzeugen wie madExcept oder JclDebug zeigen auf den Handler statt auf den ursprünglichen Fehler, die Absprungstelle geht verloren. raise; wirft die aktuelle Excep' +
    'tion unverändert weiter. Auch raise E at … wird gemeldet, dann ohne Korrektur. Still, wenn der Handler das Objekt mit AcquireExceptionObject übernimmt oder der Variablen ein neues Objekt zuweist, in a' +
    'nonymen Methoden und bei Handlern ohne Variablennamen. Konfidenz hoch. Korrektur: raise E; → raise;."',
    '    },',
    '    {',
    '      "id": "blocking-call-in-main-thread",',
    '      "name": "Blockierender Aufruf im Hauptthread",',
    '      "description": "Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects oder Wait in Methoden von Formularen und Frames (Klassen, die von TForm, TCustomForm, TFrame oder TCustomFrame erben) ' +
    'und in Ereignis-Handlern (Methoden mit Parameter Sender) außerhalb von Thread-Klassen. Die Oberfläche friert ein, solange der Aufruf wartet; wartet der andere Thread auf Synchronize, hängt das Program' +
    'm. WaitFor ohne Timeout auf einer Variablen nennt die Gefahr der Synchronize-Verklemmung. Sleep, WaitForSingleObject und WaitForMultipleObjects zählen nur ohne Empfänger (oder mit Winapi.Windows), Wai' +
    'tFor und Wait nur mit Empfänger. Ein Literal-Timeout unter maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) bleibt still, außer ein kurzes Sleep in einer Warteschleife ohne Application.ProcessMessage' +
    's. Anonyme Methoden sind ausgenommen (TTask.Run, TThread.Queue), eingebettete Routinen gehören zu ihrer Methode. Konfidenz mittel. Keine Schnellkorrektur: die Arbeit in TTask.Run auslagern und das Erg' +
    'ebnis mit TThread.Queue melden.",',
    '      "options": [',
    '        {',
    '          "name": "maxSleepMs",',
    '          "description": "Literal-Timeouts unter diesem Wert (Millisekunden) werden nicht gemeldet; ein kurzes Sleep in einer Warteschleife schon."',
    '        },',
    '        {',
    '          "name": "calls",',
    '          "description": "Aufrufe, die blockieren. Andere Namen werden unabhängig von ihren Argumenten gemeldet."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "thread-loop-without-terminated",',
    '      "name": "Thread-Schleife ohne Terminated",',
    '      "description": "Eine while- oder repeat-Schleife in TThread.Execute oder in einer Methode der Thread-Klasse, die nur von dort aufgerufen wird (auch über andere solche Methoden, eingebettete Rout' +
    'inen eingeschlossen), prüft Terminated nicht. Terminate wirkt dann nicht, und WaitFor bzw. Free hängen beim Beenden. Gemeldet für Endlosschleifen (while True, until False) und für Warteschleifen mit S' +
    'leep, WaitFor, WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait oder Yield, deren Bedingung und Rumpf Terminated bzw. CheckTerminated nie erwähnen. Thread-Klassen kommen au' +
    's der Unit und dem Index. Begrenzte Schleifen, for-Schleifen, anonyme Methoden und Klassen, die TerminatedSet überschreiben (sie beenden ihre Schleifen auf anderem Weg), bleiben still. Konfidenz hoch.' +
    ' Korrektur: Terminated in die Schleifenbedingung aufnehmen (while True → while not Terminated, sonst and not Terminated; until False → until Terminated, sonst or Terminated)."',
    '    },',
    '    {',
    '      "id": "anonymous-thread-not-started",',
    '      "name": "Anonymer Thread nie gestartet",',
    '      "description": "TThread.CreateAnonymousThread(…) legt den Thread angehalten und mit FreeOnTerminate an. Ohne Start läuft er nie, und weil er nie endet, wird er auch nie freigegeben. Gemeldet für' +
    ' den Aufruf als eigene Anweisung und für eine lokale Variable (auch Inline-Variable), die weder mit Start oder Resume gestartet noch weitergegeben wird (Argument, Zuweisung, Result, Feld). Eigenschaft' +
    'en wie FreeOnTerminate oder OnTerminate zu setzen gilt nicht als Weitergabe. Konfidenz hoch. Korrektur: .Start anhängen; bei einer Variablen T.Start; nach der letzten Anweisung desselben Blocks, die s' +
    'ie erwähnt."',
    '    },',
    '    {',
    '      "id": "task-exception-unobserved",',
    '      "name": "Exception in TTask geht verloren",',
    '      "description": "TTask.Run(…) bzw. TTask.Create(…).Start, dessen Ergebnis nicht gespeichert und nie mit Wait, Status o. ä. abgefragt wird und dessen anonyme Methode kein try … except hat. Eine Ex' +
    'ception im Task verschwindet still. Auch gemeldet für eine lokale Variable, die nie wieder vorkommt (bei TTask.Create nur in V.Start). Still bei gespeicherten Ergebnissen (Felder, Result, jede andere ' +
    'Verwendung der Variablen) und bei Methodenzeigern, deren Rumpf die Regel nicht sieht. Konfidenz mittel. Korrektur: den Rumpf in try … except einschließen und die Meldung über TThread.Queue mit ShowMes' +
    'sage im Hauptthread zeigen (ergänzt Vcl.Dialogs, in FireMonkey-Units FMX.Dialogs, und System.SysUtils im uses, wenn sie fehlen); nur, wenn begin und end der anonymen Methode auf eigenen Zeilen stehen.' +
    '"',
    '    },',
    '    {',
    '      "id": "dataset-loop-without-next",',
    '      "name": "Datenmengen-Schleife ohne Next",',
    '      "description": "while not Q.Eof do ohne Q.Next im Rumpf oder mit Next nur auf einem Teil der Wege, die die Schleife fortsetzen (if ohne else, Continue vor Next). Die Schleife dreht endlos auf de' +
    'mselben Datensatz. Delete, MoveBy, Last, Close, FindNext und Free zählen ebenfalls als Weiterbewegen; Break, Exit, Abort und raise beenden die Schleife. Innere while- und for-Schleifen laufen vielleic' +
    'ht nie und zählen nicht. Wird Q im Rumpf weitergegeben (Argument, Zuweisung, with), kann der Aufgerufene den Zeiger bewegen, und die Regel bleibt still. Konfidenz hoch, wenn Next ganz fehlt, mittel, w' +
    'enn nur einzelne Wege es auslassen. Korrektur: Q.Next; am Ende des begin … end-Rumpfs einfügen (nur, wenn Next ganz fehlt)."',
    '    },',
    '    {',
    '      "id": "dataset-edit-without-post",',
    '      "name": "Edit oder Append ohne Post",',
    '      "description": "Nach Edit, Append oder Insert (ohne Argumente) einer Datenmenge ruft dieselbe Routine weder Post noch Cancel (noch CheckBrowseMode) auf. Die Änderung bleibt offen und geht beim S' +
    'crollen still verloren oder wird später unerwartet gespeichert; bei einer Exception dazwischen bricht sie niemand ab. Still, wenn eine andere Routine der Unit dieselbe Datenmenge postet oder abbricht ' +
    '(Bearbeiten-Knopf mit eigenem Speichern-Knopf), und wenn die Datenmenge nach Edit weitergegeben wird (Argument, Zuweisung, with). Konfidenz mittel. Korrektur: die folgenden Anweisungen, die die Datenm' +
    'enge benutzen, in try … except einschließen, mit Post am Ende des try-Teils und Cancel; raise; im except-Teil."',
    '    },',
    '    {',
    '      "id": "transaction-without-rollback",',
    '      "name": "Transaktion ohne Rollback",',
    '      "description": "StartTransaction ohne Rollback im except des unmittelbar folgenden try. Bei einer Exception bleibt die Transaktion offen und hält Sperren. Erkannt für FireDAC (TFDConnection, TFD' +
    'Transaction), IBX und dbExpress (StartTransaction/Commit/Rollback), dbExpress ab XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, auch als T := Conn.BeginTransaction) und ADO (BeginTrans/Comm' +
    'itTrans/RollbackTrans). Die Option pairs ersetzt diese Paare durch eigene. Das Rollback darf in einem try … except innerhalb eines direkt folgenden try … finally stehen. Still, wenn eine andere Routin' +
    'e der Unit dieselbe Verbindung zurückrollt (Transaktion über mehrere Ereignisse). Konfidenz hoch. Korrektur: die Anweisungen bis zum Commit desselben Blocks in try … except mit Rollback (mit den Argum' +
    'enten des Commit) und raise; einschließen; nur, wenn im selben Block ein Commit folgt.",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "description": "Transaktionsmethoden je Bibliothek als [{\"start\": …, \"commit\": …, \"rollback\": …}]; ersetzt die eingebauten Paare."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "sql-write-without-where",',
    '      "name": "UPDATE oder DELETE ohne WHERE",',
    '      "description": "UPDATE oder DELETE ohne WHERE in einem String-Literal, in SQL.Text, SQL.Add, CommandText, im ersten Argument von ExecSQL, ExecSQLScalar, Open, ExecuteDirect oder Execute oder in ' +
    'SQL.Strings/CommandText der Formulardatei. Das betrifft alle Zeilen der Tabelle; meist ist die Bedingung vergessen. Die Regel setzt den SQL-Text je Query innerhalb einer Routine zusammen (Clear und ei' +
    'n neuer Text beginnen von vorn) und setzt Konstanten und lokale Werte ein. JOIN, TOP, LIMIT und ROWS schränken die Zeilen ebenfalls ein; ein WHERE in einer Unterabfrage oder einem Kommentar zählt nich' +
    't. Unbekannte Teile hinter dem Tabellennamen (Variablen, Aufrufe an der Stelle einer Klausel) lassen die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer Konfidenz. Still, wenn die R' +
    'outine den SQL-Text weitergibt oder eine andere Routine der Unit ihn ergänzt; SQL der Formulardatei zählt nur, solange die Unit es nicht verändert. Literale außerhalb von SQL-Eigenschaften zählen nur ' +
    'mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte still bleiben. Konfidenz hoch, keine Korrektur; Tabellen, die absichtlich geleert werden, gehören in allowTables.",',
    '      "options": [',
    '        {',
    '          "name": "allowTables",',
    '          "description": "Tabellen, die absichtlich ganz geleert bzw. geändert werden, mit oder ohne Schema."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "signature-mismatch",',
    '      "name": "Implementierung weicht von der Deklaration ab",',
    '      "description": "Der Kopf im implementation-Teil hat andere Parameter (Anzahl, Name, Typ, const/var/out), einen anderen Ergebnistyp, procedure statt function oder eine andere Aufrufkonvention als' +
    ' die Deklaration im Typ oder, bei einer Routine der Unit, im interface-Teil (wie E2037). Bei Überladungen wird die nächstliegende Deklaration verglichen (Parameteranzahl, dann Typen, Namen und Modifiz' +
    'ierer); ist sie nicht eindeutig, melden declared-not-implemented und implemented-not-declared beide Seiten. Routinen der Unit vergleicht die Regel nur bei eindeutigem Namen und ohne overload, external' +
    ' und forward. Ein Rumpf darf Parameterliste, Ergebnistyp und Aufrufkonvention weglassen. Methoden in {$IF}-Blöcken werden übergangen; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Kopf der ' +
    'Implementierung an die Deklaration angleichen oder als zweite Aktion die Deklaration an die Implementierung (Standardwerte bleiben in der Deklaration). refactoring.syncSignatures = false entfernt nur ' +
    'die Korrekturen."',
    '    },',
    '    {',
    '      "id": "interface-not-implemented",',
    '      "name": "Interface-Methode fehlt in der Klasse",',
    '      "description": "Eine Klasse nennt ein Interface, implementiert aber nicht alle seine Methoden, auch die der Vorfahr-Interfaces (wie E2291). Eine gleichnamige Methode der Klasse mit anderer Signa' +
    'tur wird an dieser Methode gemeldet (wie E2211). Geerbte Methoden der Vorfahrklassen, Methodenzuordnungen (procedure IFoo.Bar = Baz) und Properties mit implements zählen; ebenso die öffentlichen Metho' +
    'den von TObject und die IInterface-Methoden von TInterfacedObject und ähnlichen RTL-Basen. Endet die Kette der Vorfahrklassen bei einer unbekannten Klasse oder ist das Interface unbekannt, bleibt die ' +
    'Regel still. Gemeldet wird auch eine Methodenzuordnung für ein Interface, das die Klasse nicht nennt (wie E2265). Klassen in {$IF}-Blöcken werden übergangen. Korrektur: fehlende Methoden deklarieren u' +
    'nd leer implementieren (nicht bei abweichendem Kopf)."',
    '    },',
    '    {',
    '      "id": "uses-unit-not-found",',
    '      "name": "Unit in uses nicht gefunden",',
    '      "description": "Eine Unit aus uses oder contains liegt weder im Projekt noch in den Ordnern, die der Compiler durchsucht: Ordner der verwendenden Datei, Projektordner, Suchpfade und DCU-Ausgabeo' +
    'rdner der .dproj, Bibliothekspfade der Installation, jeweils als .pas oder .dcu und mit jedem Unit-Namespace davor (SysUtils → System.SysUtils); bei Packages zusätzlich die Units der requires-Packages' +
    ' (wie F2613). Ebenso gemeldet: eine Datei aus in ''…'', die es nicht gibt (F1026, auch ohne Projekt, denn es zählt nur der Pfad relativ zur verwendenden Datei), ein Package aus requires, das weder als .' +
    'dpk noch als .dcp gefunden wird (E2202), eine Unit, die sich selbst einbindet (F2092), und einmal eine fehlende Unit System, also ein fehlender Bibliothekspfad, statt einer Meldung je Unit (F1027). Ei' +
    'nträge in {$IF}-Blöcken werden übergangen; ohne bekannte Installation, mit offenem Makro in einem Suchpfad oder einem requires-Package mit unbekanntem Inhalt bleibt die Regel still. Die Meldung nennt ' +
    'ähnliche Units. Korrekturen: die Unit mit Namespace (Forms → Vcl.Forms) bzw. eine ähnlich geschriebene einsetzen oder den Ordner unter dem Projekt, in dem die Unit liegt, in DCC_UnitSearchPath der Bas' +
    'iskonfiguration der .dproj aufnehmen.",',
    '      "options": [',
    '        {',
    '          "name": "searchPaths",',
    '          "description": "Wo Units gesucht werden: project (wie der Compiler: Projekt, Suchpfade der .dproj, Bibliothekspfade, .pas und .dcu), atlas (was Atlas kennt: Index und Quellpfade der Installa' +
    'tion) oder both."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unresolved-attribute",',
    '      "name": "Attribut nicht gefunden und still ignoriert",',
    '      "description": "Ein Attribut [Name] lässt sich weder einer Klasse NameAttribute noch Name zuordnen, meist weil eine Unit in uses fehlt. Delphi warnt nur (W1074, nach {$WARN UNKNOWN_CUSTOM_ATTRIB' +
    'UTE ERROR} E1074) und übergeht das Attribut: DUnitX-Tests laufen dann nicht, JSON- oder ORM-Zuordnungen fehlen. Die Meldung nennt die Unit, die das Attribut im Index deklariert; eine Fassaden-Unit, di' +
    'e den Typ aus einer anderen Kandidatin weiterreicht (DUnitX.TestFramework statt DUnitX.Attributes), geht vor, und die DUnitX-Attribute sind auch ohne DUnitX im Index bekannt. Attribute des Compilers w' +
    'ie Weak, Unsafe, Ref und Volatile zählen immer. Still ohne die Unit System im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das Attribut deklarieren), in {$IF}-Blöcken und bei unbeka' +
    'nntem Vorfahren der umgebenden Klasse; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Unit in uses aufnehmen."',
    '    },',
    '    {',
    '      "id": "comparison-as-statement",',
    '      "name": "Vergleich statt Zuweisung als Anweisung",',
    '      "description": "Ein Vergleich wie Result = 0; oder FAktiv = True; steht als eigene Anweisung; gemeint war :=. Delphi meldet E2014 erst beim Übersetzen. Bei = mit zuweisbarer linker Seite (Variab' +
    'le, Feld, Element, Ziel eines Zeigers) ersetzt die Korrektur = durch :=. Andere Vergleiche und Ausdrücke, deren Wert verfällt (A <> B;, A + B;, not A;, ein Literal), meldet die Regel ohne Korrektur, e' +
    'benso einen Aufruf links."',
    '    },',
    '    {',
    '      "id": "duplicate-case-label",',
    '      "name": "Doppelte case-Marke",',
    '      "description": "Zwei Marken einer case-Anweisung decken denselben Wert ab (wie E2030), auch über Bereiche (1..5 und 3), Konstanten mit gleichem Wert, Zeichen (''a'' und #97) und Bereiche von Aufzä' +
    'hlungswerten. Gleiches gilt für die Marken eines varianten Record-Teils (wie E2027). Die Werte ergeben sich aus Zahlen, Zeichen, Konstanten und Aufzählungswerten über die Namensauflösung; Marken mit u' +
    'nbekanntem Wert vergleicht die Regel nur über den Text. Gemeldet wird eine Marke nur, wenn die frühere immer mit übersetzt wird: verschiedene Zweige desselben {$IF} stoßen nie zusammen. Korrektur: den' +
    ' doppelten Wert aus dem späteren Zweig entfernen bzw. den ganzen Zweig, wenn es seine einzige Marke war; eine teilweise Überschneidung von Bereichen meldet die Regel ohne Korrektur."',
    '    },',
    '    {',
    '      "id": "field-after-method",',
    '      "name": "Feld nach Methoden im selben Abschnitt",',
    '      "description": "In einem Sichtbarkeitsabschnitt einer Klasse, eines Objekts oder Records folgt eine Felddeklaration auf eine Methode oder Property. Delphi verlangt Felder zuerst oder einen neuen' +
    ' Abschnitt bzw. var (E2169); FPC übersetzt das. Korrekturen: das Feld samt Attributen und Kommentaren an den Anfang des Abschnitts verschieben oder var davor setzen. In Records steht var vorn, weil da' +
    's Verschieben das Speicherlayout ändert. Gemeldet wird ein Feld nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird; mit bedingten Zweigen dazwischen gibt es nur var."',
    '    },',
    '    {',
    '      "id": "overload-directive-missing",',
    '      "name": "Überladung ohne overload oder mit gleicher Signatur",',
    '      "description": "Zwei Routinen oder Methoden gleichen Namens im selben Gültigkeitsbereich (ein Typ, die Unit über interface und implementation, die in einer Routine verschachtelten Routinen), von' +
    ' denen mindestens eine kein overload trägt (wie E2254, bzw. E2267, wenn es der früheren fehlt), oder zwei Überladungen mit gleichen Parameterarten und -typen (wie E2252, bzw. E2301 mit auch gleichem E' +
    'rgebnistyp). Ein Rumpf zu einer früheren Deklaration (interface, forward) zählt nicht. Operatoren, Methodenrümpfe und Deklarationen in verschiedenen Zweigen desselben {$IF} bleiben außen vor. Korrektu' +
    'r: overload; an alle Deklarationen ohne anhängen, vor den übrigen Direktiven."',
    '    },',
    '    {',
    '      "id": "duplicate-declaration",',
    '      "name": "Bezeichner doppelt deklariert",',
    '      "description": "Ein Bezeichner ist im selben Gültigkeitsbereich zweimal deklariert (wie E2004): lokale Variable, Konstante, Typ oder Label und ein Parameter der Routine, zwei Felder, ein Feld un' +
    'd eine Methode oder Property eines Typs, zwei Typen, Konstante und Variable der Unit über interface und implementation hinweg. Ebenso eine Unit doppelt in uses oder in den uses-Klauseln von interface ' +
    'und implementation zugleich (Option checkUses). Überladungen und Rümpfe von Routinen, eine Vorwärtsdeklaration und ihr Typ, TList neben TList<T> und Deklarationen in verschiedenen Zweigen desselben {$' +
    'IF} zählen nicht. Korrektur: zweite Deklaration entfernen (den ganzen var-, const-, type- oder label-Abschnitt, wenn sie seine einzige war; bei uses den doppelten Eintrag); keine bei Parametern, Metho' +
    'den und Properties. Unter demselben Namen überladene default-Array-Properties prüft default-property-invalid (#1380).",',
    '      "options": [',
    '        {',
    '          "name": "checkUses",',
    '          "description": "Doppelte Einträge in uses-Klauseln melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "conditional-directive-unbalanced",',
    '      "name": "Bedingte Direktiven unvollständig oder unbekannt",',
    '      "description": "Ein {$IFDEF}, {$IFNDEF}, {$IFOPT} oder {$IF}, das nie geschlossen wird, sodass der Rest der Datei an seiner Bedingung hängt (wie E2095, bei {$IF} E2280); {$ELSE}, {$ELSEIF}, {$EN' +
    'DIF} oder {$IFEND} ohne passendes {$IF…} oder nach {$ELSE} (wie E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} oder {$UNDEF} ohne gültiges Symbol (wie E2173); eine unbekannte Direktive oder ein unbekannter {$' +
    'WARN}-Bezeichner (wie E1030, vor Delphi 13 W1030; der Code folgt delphiVersion), mit dem nächstliegenden bekannten Namen als Korrektur; {$POPOPT} ohne {$PUSHOPT} (wie W1078) oder {$PUSHOPT} ohne {$POP' +
    'OPT} (wie W1079); ein ungültiger Wert für {$ALIGN} bzw. {$A} (wie E2573). Unbekannte Namen prüft die Regel nicht in Zweigen, deren Bedingung FPC abfragt, {$PUSHOPT}/{$POPOPT} nur, wenn keines davon in' +
    ' einem bedingten Zweig steht. Korrekturen: {$ENDIF} vor der ersten Leerzeile hinter dem offenen Block ergänzen, überzählige Direktive entfernen, Tippfehler korrigieren."',
    '    },',
    '    {',
    '      "id": "compiler-directive-invalid",',
    '      "name": "Compileranweisung ungültig oder Datei aus {$I}/{$R} fehlt",',
    '      "description": "Eine Compileranweisung außerhalb bedingter Zweige, die dcc ablehnt oder selbst meldet: {$MESSAGE WARN ''Text''} und {$MESSAGE HINT ''Text''} zeigen ihren Text als Warnung bzw. Hinwei' +
    's (wie W1054, H1054); {$WEAKPACKAGEUNIT ON} zusammen mit {$DENYPACKAGEUNIT ON} (wie E2222); {$DESIGNONLY} oder {$RUNONLY} in einer Unit statt in einem Package (wie E2224); {$OBJTYPENAME} für einen sch' +
    'lichten Alias wie TZahl = Integer (wie E2560); {$CODEPAGE} mit einer Zahl über 65535 (wie E1030); eine Datei aus {$I} bzw. {$INCLUDE}, die es weder neben der Unit noch in den Suchpfaden des Projekts g' +
    'ibt (wie F1026); eine Include-Datei, die sich über unbedingte {$I} selbst einbindet, direkt oder über weitere Include-Dateien (wie E2245); eine Ressourcendatei aus {$R} bzw. {$RESOURCE}, die sich nich' +
    't finden lässt (wie E1026). Dateien sucht die Regel wie dcc: neben der Unit, im Projektordner, in den Suchpfaden, DCC_IncludePath, DCC_ResourcePath und den Bibliothekspfaden der Installation; ohne Pro' +
    'jekt, mit unbekannter Installation oder offenem Makro in einem Pfad bleibt sie still. Nicht geprüft: {$R Name.res Name.rc} und eine .res neben einer gleichnamigen .rc (die IDE übersetzt sie vor dem Co' +
    'mpiler), Formulare ({$R *.dfm}, form-resource-missing), Masken wie {$R *.res}, Schalter wie {$I+} und {$R-} sowie {$MESSAGE} ohne Art oder mit ERROR bzw. FATAL. Direktiven in bedingten Zweigen übergeh' +
    't die Regel, denn dcc meldet nur, was es übersetzt."',
    '    },',
    '    {',
    '      "id": "override-target-missing",',
    '      "name": "override ohne passende virtuelle Methode",',
    '      "description": "Eine Methode mit override, zu der kein Vorfahr eine virtuelle (oder dynamic, abstract) Methode mit gleichem Namen und gleichen Parametern hat (wie E2137): oft ein Tippfehler (Des' +
    'tory) oder im Vorfahren geänderte Parameter. Die Meldung nennt die nächstliegende virtuelle Methode des Vorfahren („dort heißt es Ausfuehren(const Modus: TModus)“) bzw. einen ähnlichen Namen. Außerdem' +
    ': override auf eine statische Methode (wie E2170), auf eine finale (wie E2352) und Ableiten von einer sealed-Klasse (wie E2353). Vorfahren sucht die Regel in der Datei und im Symbolindex; bricht die K' +
    'ette an einer unbekannten Klasse ab, bleibt sie still. Ohne System im Index gelten die virtuellen Methoden von TObject als vorhanden. Typparameter generischer Vorfahren, Typaliase und Synonyme wie Lon' +
    'gint passen. Korrektur: Signatur des Vorfahren in Deklaration und Implementierung übernehmen."',
    '    },',
    '    {',
    '      "id": "abstract-class-instantiated",',
    '      "name": "Instanz einer Klasse mit abstrakten Methoden",',
    '      "description": "Create auf einer Klasse, die abstrakte Methoden deklariert oder erbt, ohne sie zu überschreiben (wie W1020). Eine als abstract deklarierte Klasse ohne abstrakte Methoden lässt si' +
    'ch erzeugen; dcc setzt \"class abstract\" nicht durch (E2402 gibt es nur unter .NET, #1383). Der Aufruf einer abstrakten Methode löst zur Laufzeit EAbstractError aus; die Meldung nennt die offenen Met' +
    'hoden. Klassen sucht die Regel in der Datei und im Symbolindex; Überladungen mit gleicher Parameterzahl gelten als eine Methode. Aufrufe über Klassenreferenzen, inherited Create und Konstruktor-Rümpfe' +
    ' prüft sie nicht. Korrektur für eine Klasse dieser Datei, die die abstrakten Methoden erbt: dort überschreiben (wie die Code-Aktion „überschreiben“)."',
    '    },',
    '    {',
    '      "id": "property-accessor-invalid",',
    '      "name": "Getter oder Setter einer Property ungültig",',
    '      "description": "Der Name hinter read oder write einer Property passt nicht: Er ist weder in der Klasse noch in ihren Vorfahren deklariert oder ist eine Property (wie E2168); Getter oder Setter h' +
    'aben die falsche Art, Parameter oder Typen (wie E2008, ältere Delphi-Versionen E2234); der Setter nimmt einen var- oder out-Parameter (wie E2282); die Zugriffsmethode ist überladen, und keine Überladu' +
    'ng passt (wie E2250, ältere Delphi-Versionen E2271); eine Klassen-Property nutzt ein Instanzmitglied oder eine Klassenmethode ohne static (wie E2355), eine Instanz-Property eine class var oder eine st' +
    'atische Klassenmethode (wie E2356); eine Array-Property nutzt ein Feld (wie E2008 in Delphi 13, dokumentiert als E2174, index mit Feld übersetzt dcc); ein Feldselektor geht über ein Feld, das kein Rec' +
    'ord ist, oder steht hinter einer Klassen-Property (wie E2459), nennt ein Mitglied, das kein Feld ist (wie E2461), oder ein Feld, das dem Record fehlt (wie E2562). Namen sucht die Regel in der Datei un' +
    'd für Vorfahren im Symbolindex; sie bleibt still, wenn die Kette der Vorfahren abbricht, der Name nur in einem inaktiven Zweig steht, die Klasse ihn nicht sieht oder Include-Dateien einbindet. Typen v' +
    'ergleicht sie nur, wenn beide eingebaut oder als eigener Typ deklariert sind. Korrektur für ein fehlendes F<Name>, Get<Name> oder Set<Name>: anlegen (wie die Vervollständigung hinter read/write, compl' +
    'etion.accessorSection)."',
    '    },',
    '    {',
    '      "id": "assign-to-property-member",',
    '      "name": "Zuweisung an ein Feld eines Property-Records",',
    '      "description": "Zuweisung an ein Feld eines Records, den eine Property mit Getter, eine Default- oder Array-Property oder ein Funktionsergebnis nur als Kopie liefert (wie E2064): Die Zuweisung h' +
    'at keine Wirkung. Zuweisungen an untypisierte Konstanten meldet die Regel ebenso. Typen kommen aus der Namensauflösung; gemeldet wird nur bei sicher bekanntem Record-Typ. Liest die Property direkt ein' +
    ' Feld, schreibt Delphi in dieses Feld, und die Regel bleibt still. Korrektur bei einer Property mit write: über eine lokale Variable zuweisen und zurückschreiben; die Variable wird in der Routine dekl' +
    'ariert, die Unit ihres Typs in uses ergänzt."',
    '    },',
    '    {',
    '      "id": "readonly-property-assigned",',
    '      "name": "Zuweisung an eine Property ohne write",',
    '      "description": "Zuweisung an eine Property ohne write (wie E2129) bzw. Lesen einer Property ohne read (wie E2130). Die Regel meldet nur, wenn die Namensauflösung die Property sicher findet; Neud' +
    'eklarationen ohne read und write (property Caption;) gelten als unbekannt. Korrekturen: Count := 0 wird Clear, wenn der Typ Clear hat; in einer Methode der deklarierenden Klasse das Feld hinter read z' +
    'uweisen; für eine Property dieser Datei den Setter anlegen und write ergänzen."',
    '    },',
    '    {',
    '      "id": "sql-select-star",',
    '      "name": "SELECT * im Code",',
    '      "description": "SELECT * oder SELECT Alias.* in einer Spaltenliste, an denselben Stellen wie bei sql-write-without-where: String-Literale, SQL.Text, SQL.Add, CommandText, das erste Argument von ' +
    'ExecSQL, Open und ähnlichen Aufrufen, Konstanten, lokale Werte und SQL.Strings/CommandText der Formulardatei. Neue Spalten ändern still die Datenmenge, persistente Felder passen nicht mehr, und es wer' +
    'den mehr Daten übertragen als nötig. Unterabfragen zählen; EXISTS (SELECT * …) und COUNT(*) bleiben still, ebenso eine Spaltenliste aus einer Variablen. Literale außerhalb von SQL-Eigenschaften zählen' +
    ' nur mit SELECT in Großbuchstaben und einem FROM, damit Meldungstexte still bleiben. Standardmäßig aus (in den Regeleinstellungen oder mit dem Profil strict einschalten). Konfidenz hoch. Schnellkorrek' +
    'tur: Steht der Stern in einem einzelnen Literal und hat die Datenmenge persistente Felder in der Formulardatei, ersetzt sie * durch deren FieldName-Liste (ohne berechnete und Nachschlagefelder)."',
    '    },',
    '    {',
    '      "id": "path-concat-without-delimiter",',
    '      "name": "Pfad ohne Trennzeichen zusammengesetzt",',
    '      "description": "Ein Ordner ohne abschließendes Trennzeichen wird mit + an einen Datei- oder Ordnernamen gehängt: Ergebnisse von ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHo' +
    'mePath, TPath.GetDocumentsPath und den übrigen TPath.Get…Path-Ordnern, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory und TDirectory.GetParent, direkt aufgerufen oder in einer lokalen Variable' +
    'n, der die Routine nur solche Werte zuweist. Das Ergebnis ist C:\\Datendatei.txt statt C:\\Daten\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter und TPath.GetTempPath enden mit einem Trennze' +
    'ichen und bleiben still, ebenso Trennzeichen, Endungen (ExtractFileExt, ''.bak'') und Texte, die mit Leerzeichen oder Satzzeichen beginnen. Ein Literal als Name meldet mit hoher, ein Bezeichner mit mitt' +
    'lerer Konfidenz. Geht eine lokale Variable an eine Prozedur außer ForceDirectories, FileExists und ähnlichen lesenden Aufrufen, kann sie dort geändert werden und bleibt still. Schnellkorrektur: TPath.' +
    'Combine(Ordner, Name), System.IOUtils wird in die uses eingetragen."',
    '    },',
    '    {',
    '      "id": "hardcoded-path",',
    '      "name": "Fester Dateipfad im Code",',
    '      "description": "Ein String-Literal mit Laufwerksbuchstaben (C:\\…, auch mit /) oder UNC-Pfad (\\\\server\\freigabe\\…); Pfade unter C:\\Users bzw. C:\\Documents and Settings bekommen eine eigene' +
    ' Meldung. Auf anderen Rechnern fehlt der Pfad. Laufwerkswurzeln wie ''C:\\'' allein und die Präfixe \\\\?\\ und \\\\.\\ bleiben still, ebenso Kommentare, Test-Units und Units aus allowUnits (z. B. eine ' +
    'Unit mit den Standardpfaden einer Installation). Konfidenz hoch, keine Korrektur: den Pfad aus TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), den Einstellungen oder einer Umgebungsvari' +
    'ablen holen.",',
    '      "options": [',
    '        {',
    '          "name": "allowUnits",',
    '          "description": "Units, in denen feste Pfade erlaubt sind, nach Unit-Namen; * am Ende passt auf ein Präfix (App.Config*)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "filename-compare-case",',
    '      "name": "Dateinamen mit = verglichen",',
    '      "description": "Ein Vergleich mit = oder <>, bei dem eine Seite ein Datei- oder Pfadname ist: das Ergebnis von ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt, ExpandFileName, C' +
    'hangeFileExt und verwandten Funktionen aus System.SysUtils, von TPath.GetFileName, GetExtension, GetDirectoryName, GetFullPath, Combine und verwandten Methoden oder eine Variable bzw. Eigenschaft, der' +
    'en Name auf FileName endet, oder Application.ExeName. Unter Windows sind Kunde.pas und kunde.PAS dieselbe Datei. Vergleiche mit Leertext, nil oder einem Literal ohne Buchstaben bleiben still, ebenso E' +
    'xtractFileDir(X) = X (beide Seiten stammen aus demselben Text). Still bleibt sie auch, wenn dieselbe Anweisung dieselben beiden Seiten ohne Groß-/Kleinschreibung vergleicht (SameText, AnsiSameText, Co' +
    'mpareText, AnsiCompareText, SameFileName, AnsiCompareFileName), etwa plattformabhängig mit PathDelim = ''\\'', und in Test-Units (Testdoubles vergleichen mit Namen, die der Test selbst vergibt). Konfide' +
    'nz mittel. Korrektur: SameFileName(A, B), bei <> not SameFileName(A, B); ergänzt System.SysUtils in der uses-Klausel, falls nötig."',
    '    },',
    '    {',
    '      "id": "initialization-not-finalized",',
    '      "name": "Beim Start erzeugtes Objekt wird nicht freigegeben",',
    '      "description": "Ein Objekt wird in initialization mit TKlasse.Create erzeugt und einer Unit-Variablen zugewiesen oder in einem class constructor erzeugt und einer class var zugewiesen, aber die ' +
    'Unit gibt es nirgends frei (kein Free, Destroy, DisposeOf, Release oder FreeAndNil in der ganzen Unit). FastMM meldet beim Beenden ein Leck; in Packages bleibt das Objekt bei jedem Entladen liegen. In' +
    'terface- und Record-Typen, Komponenten mit Owner (Application, Self, Owner) und Objekte, die die Unit weitergibt, bleiben still: Jede Erwähnung der Variablen muss harmlos sein (Zugriff auf ein Mitglie' +
    'd, Vergleich mit nil, Assigned, erneutes Create oder Zuweisung von nil); als Argument übergeben, anderswo zugewiesen, with, eine Property, die sie liest, oder FreeOnTerminate lassen die Regel schweige' +
    'n. Bei Variablen aus dem interface-Abschnitt und öffentlichen class vars schweigt sie auch, wenn eine andere Unit im Index den Namen verwendet. Konfidenz hoch. Korrektur: FreeAndNil am Ende von finali' +
    'zation bzw. im class destructor; fehlt der finalization-Abschnitt oder der class destructor (Deklaration und Rumpf), wird er angelegt, System.SysUtils kommt bei Bedarf in die uses-Klausel."',
    '    },',
    '    {',
    '      "id": "compiler-warnings-disabled",',
    '      "name": "Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet",',
    '      "description": "{$WARNINGS OFF}, {$HINTS OFF}, {$WARN X OFF}, {$R-}, {$Q-} (auch zusammen als {$R-,Q-}) oder die langen Formen {$RANGECHECKS OFF} und {$OVERFLOWCHECKS OFF} ohne spätere Wiederher' +
    'stellung bis zum Ende der Unit. Meldungen und Prüfungen verschwinden weit über die gemeinte Stelle hinaus, die 0/0/0-Regel wird unterlaufen. Jedes spätere ON, +, DEFAULT oder ERROR für denselben Schal' +
    'ter zählt als Wiederherstellung, auch in Mustern mit {$IFOPT}/{$IFDEF}, ebenso ein späteres {$POPOPT}. Ein Schalter, dessen Gegenstück in einem anderen Zweig desselben {$IF} steht ({$IFDEF DEBUG}{$R+}' +
    '{$ELSE}{$R-}{$ENDIF}), ist eine gewollte Einstellung je Konfiguration und bleibt still, ebenso eine Direktive ohne Code dahinter; {$R *.dfm} ist eine Ressource, keine Bereichsprüfung. Die Option allow' +
    ' nennt Schalter, die aus bleiben dürfen (Warnungsnamen wie SYMBOL_PLATFORM, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS). Konfidenz hoch. Korrektur: die Wiederherstellung ({$WARNINGS ON' +
    '}, {$WARN X DEFAULT}, {$R+} …) hinter dem nächsten Block einfügen; bei Bereichs- und Überlaufprüfung nur einzeln, weil {$R+} eine Prüfung einschalten kann, die das Projekt aus hat.",',
    '      "options": [',
    '        {',
    '          "name": "allow",',
    '          "description": "Schalter, die bis zum Ende der Unit aus bleiben dürfen: Warnungsnamen für {$WARN} (SYMBOL_PLATFORM), WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS; ohne Groß-/Kl' +
    'einschreibung."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "dll-export-unsafe",',
    '      "name": "Exportierte Routine nicht sicher über DLL-Grenzen aufrufbar",',
    '      "description": "Eine in exports aufgeführte Routine dieser Datei hat keine Aufrufkonvention (stdcall, cdecl, safecall, winapi oder pascal; register ist die Delphi-Konvention) oder erwartet bzw. ' +
    'liefert einen String (string, UnicodeString, AnsiString, UTF8String, RawByteString), ein dynamisches Array (TBytes, TArray<T>, …DynArray, array of T aus der Datei), ein Objekt oder ein Interface ohne ' +
    'GUID. Aufrufer aus anderen Sprachen oder Delphi-Versionen stürzen ab; Strings und dynamische Arrays liegen im Speichermanager der DLL. WideString, ShortString, PChar, offene Array-Parameter und Record' +
    's sind in Ordnung. Objekte erkennt die Regel nur sicher: Klassen der Datei, des Index und häufige RTL-Klassen; Interfaces nur aus der Datei. Routinen aus anderen Units und Überladungen, die der export' +
    's-Eintrag nicht festlegt, bleiben still. Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays erlaubt (Option allowShareMem). Die Meldung steht am Eintrag in exports' +
    '; bei Strings empfiehlt sie PChar mit Puffer und Länge. Konfidenz hoch. Korrektur: stdcall in jedem Kopf der Routine ergänzen (nur einzeln, weil das die Schnittstelle für vorhandene Aufrufer ändert)."' +
    ',',
    '      "options": [',
    '        {',
    '          "name": "allowShareMem",',
    '          "description": "Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays in exportierten Routinen erlaubt."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "destructor-not-nil-safe",',
    '      "name": "Destruktor benutzt Felder, die nil sein können",',
    '      "description": "Wirft ein Konstruktor, ruft Delphi sofort den Destruktor auf, obwohl noch nicht alle Felder angelegt sind. Gemeldet wird ein Zugriff im Destruktor (oder in einer privaten Methode' +
    ', die nur der Destruktor aufruft) auf ein Feld wie FZeilen.Clear, FDatei.Position oder FZeilen[0], wenn ein Konstruktor der Klasse das Feld (TKlasse.Create) erst nach einem Aufruf anlegt, der werfen k' +
    'ann, oder nur auf manchen Wegen. Die Zugriffsverletzung verdeckt dann die eigentliche Exception. Free, FreeAndNil, DisposeOf und Zugriffe nach Assigned(FFeld) bzw. FFeld <> nil sind nil-sicher; Before' +
    'Destruction läuft auf diesem Weg nicht. Konstruktoren von RTL-Klassen, die höchstens EOutOfMemory werfen (TStringList.Create, TObjectList<T>.Create(True)), inherited Create und Supports zählen nicht a' +
    'ls werfend. Konfidenz hoch. Schnellkorrektur: if Assigned(FFeld) then vor die Anweisung setzen. Mit onlyAfterRaisingCode aus zählt jedes im Konstruktor angelegte Feld.",',
    '      "options": [',
    '        {',
    '          "name": "onlyAfterRaisingCode",',
    '          "description": "Nur melden, wenn der Konstruktor vor dem Anlegen des Felds etwas aufruft, das eine Exception werfen kann."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "handle-leak",',
    '      "name": "Windows-Handle wird nicht geschlossen",',
    '      "description": "Ein Windows-Handle in einer lokalen Variablen wird auf einem Weg zum Ende der Routine nicht mit dem passenden Gegenstück geschlossen: CreateFile, CreateEvent, CreateMutex, OpenPr' +
    'ocess, CreateProcess (hProcess, hThread) und CreateToolhelp32Snapshot mit CloseHandle, FindFirstFile mit FindClose, RegOpenKeyEx/RegCreateKeyEx mit RegCloseKey, LoadLibrary mit FreeLibrary, GetDC mit ' +
    'ReleaseDC, CreatePen/CreateBrush/CreateFont/CreateBitmap mit DeleteObject, CreateCompatibleDC mit DeleteDC und weitere. Zurückgeben, Speichern in einem Feld oder einer globalen Variablen, Übergabe an ' +
    'eine unbekannte Routine, Speichern in einem Array ([H] in einem Ausdruck) und Verwenden in einer anonymen Methode gelten als Weitergabe. Zweige, in denen eine if-Prüfung sagt, dass das Öffnen misslang' +
    ' (H = 0, H = INVALID_HANDLE_VALUE, RegOpenKeyEx(...) <> ERROR_SUCCESS), und Ausnahmewege (siehe pair-without-finally) zählen nicht. Die Option pairs ergänzt eigene Paare. Konfidenz mittel. Schnellkorr' +
    'ektur, wenn das Handle nie geschlossen wird: die Anweisungen nach dem Öffnen in try … finally mit dem Schließen einschließen bzw. das Schließen anhängen, wenn das Öffnen die letzte Anweisung ist.",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "description": "Zusätzliche Paare aus Öffnen und Schließen als \"Oeffnen>Schliessen\" oder {\"open\": …, \"close\": …}; die Öffnen-Funktion liefert das Handle, die Schließen-Prozedur bekommt' +
    ' es als einziges Argument."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "global-formatsettings-modified",',
    '      "name": "Globale FormatSettings wird verändert",',
    '      "description": "Zuweisung an die globale FormatSettings oder eines ihrer Felder (auch an die veralteten globalen Variablen DecimalSeparator, ShortDateFormat, ThousandSeparator … älterer Delphi-V' +
    'ersionen). Das ändert die Formatierung für die ganze Anwendung, für alle Packages im selben Prozess (im IDE-Plugin die IDE selbst) und für alle Threads und ist nicht threadsicher; häufig eine Notlösun' +
    'g, um einen Punkt als Dezimaltrenner zu erzwingen. Gemeldet wird nur, wenn der Name sicher die Variable aus System.SysUtils ist: keine lokale Deklaration, kein Mitglied der Klasse oder ihrer Vorfahren' +
    ' (still, wenn die Kette der Vorfahren an einer unbekannten Klasse endet), nicht in with. Ergänzt format-without-settings, das Formatierungsaufrufe ohne Settings meldet. Konfidenz hoch. Schnellkorrektu' +
    'r, wenn die Routine die globalen Settings nur einmal ändert und danach etwas formatiert: lokale TFormatSettings anlegen (TFormatSettings.Invariant bei DecimalSeparator := ''.'', sonst eine Kopie von For' +
    'matSettings mit dem geänderten Feld) und an die folgenden Formatierungsaufrufe übergeben. Mit allowInProgram sind die Zuweisungen in der .dpr erlaubt.",',
    '      "options": [',
    '        {',
    '          "name": "allowInProgram",',
    '          "description": "Zuweisungen in der .dpr erlauben, etwa einmal beim Programmstart."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "component-interface-dangling",',
    '      "name": "Komponente als Interface gespeichert und freigegeben",',
    '      "description": "Ein Nachfahr von TComponent (Formular, Frame, Datenmodul, eigene Komponente) implementiert ein Interface, aber TComponent zählt keine Referenzen. Gemeldet wird das Speichern des ' +
    'Objekts als Interface in einem Feld, einer globalen Variablen oder einer Liste (FAnsicht as IBeobachter an Bus.Anmelden, FListe.Add, Register, Subscribe …, Zuweisung an ein Feld oder eine globale Vari' +
    'able, Add in TList<IFoo>/TInterfaceList), wenn dieselbe Unit das Objekt freigibt (Free, Release, DisposeOf, FreeAndNil) und es nirgends abmeldet: FreeNotification auf dem Objekt, ein anderer Aufruf am' +
    ' selben Empfänger mit dem Objekt als Argument (Abmelden, Remove, Unsubscribe …), Clear oder eine weitere Zuweisung an dasselbe Feld. Nach der Freigabe zeigt das gespeicherte Interface ins Leere. Still' +
    ' bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren an einer unbekannten Klasse endet. Ebenso gemeldet, ohne Schnellkorrektur: Nachfahren von TInterfacedObject, die so gespeichert und z' +
    'usätzlich mit Free freigegeben werden; das gespeicherte Interface hält dann ein freigegebenes Objekt, und eine Abmeldung davor gäbe es schon frei. Konfidenz mittel. Schnellkorrektur: Abmeldung vor der' +
    ' ersten Freigabe einfügen (Empfänger.Abmelden(…), wenn der Typ des Empfängers das Gegenstück hat, bzw. Feld := nil).",',
    '      "options": [',
    '        {',
    '          "name": "componentClasses",',
    '          "description": "Basisklassen ohne Referenzzählung; mit TComponent zählen auch die bekannten VCL- und FMX-Klassen (TForm, TFrame, TDataModule …)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unit-name-mismatch",',
    '      "name": "Unit-Name passt nicht zum Dateinamen",',
    '      "description": "Der Name hinter unit weicht vom Dateinamen ab, meist nach dem Umbenennen der Datei außerhalb der IDE (wie E1038, W1038). Groß-/Kleinschreibung zählt nicht, Punkte im Namen schon.' +
    ' In Programmen, Bibliotheken und Packages wird außerdem ein Eintrag uses X in ''Datei.pas'' gemeldet, dessen Datei eine andere Unit deklariert (wie E2085); die Regel liest dazu die Datei. Passt dort auc' +
    'h der Name der Unit nicht zu ihrer Datei, meldet Delphi 13 nur E1038 in der Unit, und der uses-Eintrag bleibt still. Programme, Bibliotheken und Packages selbst vergleicht sie nicht mit dem Dateinamen' +
    ', weil der Compiler das auch nicht tut. {$WARN UNIT_NAME_MISMATCH OFF} oder {$WARNINGS OFF} vor dem Unit-Namen schaltet die Regel wie den Compiler ab. Korrekturen: Unit-Namen an den Dateinamen anpasse' +
    'n (die Datei umbenennen bleibt Sache der IDE) bzw. den uses-Eintrag auf die Unit der Datei ändern."',
    '    },',
    '    {',
    '      "id": "text-after-final-end",',
    '      "name": "Text nach dem abschließenden end.",',
    '      "description": "Nach dem abschließenden end. einer Unit, eines Programms, einer Bibliothek oder eines Packages steht noch Quelltext. Der Compiler ignoriert ihn (wie W1011); meist ist es Code, de' +
    'r beim Einfügen ans Dateiende geraten ist und nie übersetzt wird. Kommentare und Direktiven werden nicht gemeldet (Option allowComments). Die Regel sucht das abschließende end. hinter dem letzten Absc' +
    'hnitt des Syntaxbaums und schweigt, solange der Parser Fehler meldet oder end. in einem {$IF…}-Zweig steht; {$WARNINGS OFF} vor end. schaltet sie ab. Schnellkorrektur: Text nach end. entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "allowComments",',
    '          "description": "Kommentare und Direktiven nach end. erlauben."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "exports-invalid",',
    '      "name": "exports-Klausel unzulässig",',
    '      "description": "Eine exports-Klausel in einer Routine (wie E2191), der Export einer threadvar, einer mit local deklarierten Routine, einer Konstanten oder eines Typs (wie E2276) oder derselbe Ex' +
    'portname zweimal über name ''…'' (wie E2287). Variablen und denselben Eintrag zweimal ohne name übersetzt Delphi 13; die meldet die Regel nicht. Namen löst die Regel nur gegen globale Deklarationen der ' +
    'Datei auf; Namen aus anderen Units und Namen mit Punkt bleiben still, ebenso zwei Einträge in sich ausschließenden {$IF…}-Zweigen. Überladene Routinen mit verschiedenen Parameterlisten oder Exportname' +
    'n gelten als verschiedene Einträge. Ergänzt dll-export-unsafe (#973). Schnellkorrektur: doppelten Eintrag entfernen."',
    '    },',
    '    {',
    '      "id": "unit-name-conflict",',
    '      "name": "Unit-Name kollidiert",',
    '      "description": "Eine Unit heißt wie eine für den Compiler reservierte Unit, System oder SysInit (wie E2272), oder {$NOINCLUDE X} nennt eine Unit, die der Compiler nicht kennt (wie E2242); dafür ' +
    'braucht die Regel die Unit-Suche des Projekts und schweigt ohne sichere Antwort. Die Quellen der RTL (source/rtl) prüft sie nicht. Nicht gemeldet: E2447, W1051 und X2421 gehören zu den Namensräumen de' +
    'r .NET-Metadaten, die dcc32/dcc64 nicht erzeugt; für E2399 nennt die Dokumentation keine Bedingung, und eine Unit Kunden neben Kunden.Daten übersetzt Delphi ohne Fehler (Spring.pas neben Spring.Collec' +
    'tions.pas). Schnellkorrektur für {$NOINCLUDE}: eine ähnlich geschriebene bekannte Unit einsetzen."',
    '    },',
    '    {',
    '      "id": "implicit-variants-unit",',
    '      "name": "Variant ohne System.Variants in uses",',
    '      "description": "Die Unit verwendet Variant oder OleVariant als Typ, ohne System.Variants in uses zu haben. Der Compiler bindet die Unit dann still ein (wie W1040) und ändert damit die Initialisi' +
    'erungsreihenfolge. Die Regel zählt Typangaben im Syntaxbaum (Variablen, Felder, Parameter, Ergebnisse, Typargumente); Variants in uses gilt auch in einem {$IF…}-Zweig und ohne Namespace. Still in Syst' +
    'em, SysInit und Variants selbst, wenn die Datei einen eigenen Typ Variant deklariert, und nach {$WARN IMPLICIT_VARIANTS OFF}. Standardmäßig aus (Profil strict). Schnellkorrektur: System.Variants in us' +
    'es aufnehmen (Variants, wenn die Unit SysUtils oder Classes ohne Namespace nennt)."',
    '    },',
    '    {',
    '      "id": "file-encoding-unsupported",',
    '      "name": "Kodierung oder Zeichen, die der Compiler nicht liest",',
    '      "description": "Die Datei ist UTF-32 kodiert (wie F2438; erkannt an der BOM, dann keine weiteren Meldungen), oder der Code außerhalb von Strings, Kommentaren und Direktiven enthält ein Zeichen, ' +
    'das der Compiler ablehnt (wie E2038): typografische Anführungszeichen aus einer Webseite oder Textverarbeitung, die ASCII-Zeichen ! \" ? \\ ` | ~ sowie Satz- und Sonderzeichen und Emoji jenseits von A' +
    'SCII. Buchstaben, Ziffern und Verbinder wie U+203F bleiben in Bezeichnern erlaubt; asm-Blöcke und {$IF…}-Zweige werden übersprungen; Steuer-, Format- und Leerzeichen melden control-char und invisible-' +
    'char. Schnellkorrektur: ein Paar Anführungszeichen auf einer Zeile wird zum String; ein einzelnes Zeichen mit eindeutigem ASCII-Gegenstück (– − × ÷ ≤ ≥ ≠, Vollbreiten-ASCII) wird ersetzt. Eine UTF-32-' +
    'Datei hat keine Schnellkorrektur; als UTF-8 mit BOM speichern."',
    '    },',
    '    {',
    '      "id": "anonymous-capture-invalid",',
    '      "name": "Anonyme Methode erfasst, was sie nicht erfassen darf",',
    '      "description": "Eine anonyme Methode greift auf einen var-, out- oder untypisierten Parameter oder auf Result einer umgebenden Routine bzw. anonymen Funktion zu (wie E2555). Der Name wird von in' +
    'nen nach außen aufgelöst (Parameter, var/const/type, lokale Routinen, Inline-Variablen, for var); in with und asm bleibt die Regel still, Deklarationen in Zweigen bedingter Übersetzung, die die Stelle' +
    ' ausschließen, zählen nicht. Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren, in der anonymen Methode nur diese verwenden und nach der Anweisung zurückschreiben, wenn die Methode si' +
    'e zuweist."',
    '    },',
    '    {',
    '      "id": "operator-declaration-invalid",',
    '      "name": "Operator falsch deklariert",',
    '      "description": "Ein class operator in einem Record ist so deklariert, wie Delphi es ablehnt: unbekannter Operatorname (wie E2393), falsche Parameterzahl (E2517), eigener Typ fehlt in den Paramet' +
    'ern (E2518) bzw. bei Implicit/Explicit in Parametern und Ergebnis (E2521), Inc/Dec mit anderem Ergebnistyp als dem ersten Parameter (E2519) oder Assign, dessen erster Parameter kein var-Parameter des ' +
    'eigenen Typs ist (E2464, E2617). Rümpfe eines unbekannten Operators oder eines class operator in einer Klasse passen zu keiner Deklaration (E2037). In Klassen, Interfaces und object-Typen lehnt Delphi' +
    ' 13 jeden class operator ab; das meldet die Regel syntax (E2123). Typen gelten als gleich, wenn ihre Namen ohne Unit-Präfix und Typargumente übereinstimmen; Aliase des eigenen Typs in der Datei halten' +
    ' die Regel still, True, False und OnesComplement gelten als bekannt. Vergleichsoperatoren mit anderem Ergebnis als Boolean übersetzt dcc (Spring4D-Kriterien); sie bleiben still. Korrekturen: nächstlie' +
    'gender Operatorname, Ergebnis wie der erste Parameter, var vor dem ersten Parameter, Parameterliste nach Vorlage; jeweils in Deklaration und Rumpf."',
    '    },',
    '    {',
    '      "id": "generic-declaration-invalid",',
    '      "name": "Generische Deklaration unzulässig",',
    '      "description": "Eine generische Deklaration, die Delphi ablehnt: Einschränkungen class und record zugleich (wie E2507), eine Einschränkung doppelt (E2603), record zusammen mit constructor (E2516' +
    '), eine Klasse neben class bzw. record (E2552), zwei Klassen (E2553), ein Einschränkungstyp, der weder Klasse noch Interface ist (E2510); Typparameter an Aufzählung, Menge, Teilbereich, Zeiger, Klasse' +
    'nreferenz, Alias oder Helfer (E2508), an Konstruktor einer Klasse, Destruktor oder Klassenkonstruktor (E2528), Operator (E2529), globaler Routine (E2530), virtueller, dynamischer, message- oder overri' +
    'de-Methode (E2533) oder Interface-Methode (E2535); class of eines parametrisierten Typs (E2548), generische Klasse, die von TCustomAttribute erbt (E2549), parametrisierter Typ als Attribut (E2565); ei' +
    'n Typparameter, der einen des umgebenden Typs verdeckt (H2509); ein Aufruf mit einer Zahl Typargumente, die keine Überladung hat (E2551, Klassen und Records der Datei mit Vorfahren aus der Datei); ein' +
    'e Methode eines generischen Typs oder eine generische Methode aus dem interface-Teil, die ein Symbol des implementation-Teils verwendet (E2506; still in with und wenn die Vorfahrenkette nicht bekannt ' +
    'ist); eine lokale Routine in einer generischen Methode oder einer Methode eines generischen Typs (E2570); type vor einem instanziierten Typ wie type TList<Integer> (E2574, Korrektur: type entfernen un' +
    'd einen Alias deklarieren). Typen zählen, wenn sie eingebaut oder in der Datei deklariert sind und, bei Klassen als Einschränkung (E2552, E2553), auch aus dem Symbolindex; unbekannte Typen halten die ' +
    'Regel still."',
    '    },',
    '    {',
    '      "id": "type-restriction-violated",',
    '      "name": "Sprachregel für Records, Inline und Helfer verletzt",',
    '      "description": "Feste Sprachregeln, die erst der Compiler meldet: virtuelle Methoden (wie E2379) oder andere virtuelle Direktiven (override, abstract, reintroduce, message, final; E2463) in Reco' +
    'rds, parameterlose Konstruktoren (E2394), Konstruktoren, deren Parameter alle Vorgabewerte haben (E2471), und Destruktoren (E2465) in Records, Klassenmethoden in Records ohne static (E2398); in Record' +
    '-Helfern virtuelle Methoden (E2598) und die übrigen virtuellen Direktiven (E2475); Felder in Helfern (class var ist erlaubt, E2599), ein Destruktor in einem Class-Helfer (E2295; Klassenkonstruktoren u' +
    'nd Helfer-Konstruktoren ohne Konstruktoraufruf übersetzt dcc, Skia4Delphi), ein Class-Helfer mit Vorfahr-Helfer für einen Typ, der nicht vom Typ des Vorfahren abstammt (E2294, nur bei bekannter Vorfah' +
    'renkette), ein Helfer als Typ einer Deklaration (E2527) oder in einem generischen Typ (E2589); mehrere Klassenkonstruktoren (E2359, sich ausschließende bedingte Zweige zählen einmal), Klassenkonstrukt' +
    'oren mit Parametern (E2360) oder virtual, dynamic bzw. message (E2534); Methoden, Properties, Klassenmitglieder, Typen und Konstanten in lokalen oder anonymen Records (E2433 bis E2437); inline an virt' +
    'uellen oder dynamischen Methoden (E2425), an Konstruktoren und Destruktoren (E2442), mit offenen Array-Parametern (E2439), mit asm-Rumpf (E2426), im interface-Teil deklariert mit Variablen oder typisi' +
    'erten Konstanten des implementation-Teils (E2441; echte Konstanten, Aufzählungswerte, Typen und Routinen übersetzt dcc, mORMot2, Clipper2, dcc-Lauf vom 29.10.2026), als lokale Routine mit Zugriff auf ' +
    'Variablen der umgebenden Routine (E2449) oder mit Aufruf eigener lokaler Routinen (E2501); lokale, absolute oder initialisierte threadvar (E2189, E2190, E2194). Die Prüfungen gelten für alle unterstüt' +
    'zten Delphi-Versionen (10 Seattle bis 13). Option disabledChecks nimmt einzelne Codes aus. Korrekturen: Direktive entfernen, static ergänzen.",',
    '      "options": [',
    '        {',
    '          "name": "disabledChecks",',
    '          "description": "Compilercodes, die die Regel nicht prüft, z. B. [\"E2425\"]."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "attribute-usage-invalid",',
    '      "name": "Attribut falsch verwendet",',
    '      "description": "Ein Attribut des Compilers steht dort, wo Delphi es ablehnt: [Weak] an einem Feld oder einer Variablen, deren Typ sicher weder Klasse noch Interface ist (eingebaute Werttypen, Re' +
    'cords, Aufzählungen, Mengen, Arrays, Zeigertypen der Datei, Aliase verfolgt; wie E2584), [Volatile] an Typ, Routine, Methode oder Property (E2325), Weak, Unsafe, Volatile oder Ref doppelt an derselben' +
    ' Deklaration (E2326; sich ausschließende Zweige zählen nicht) oder ein Attributargument, das sicher eine Variable oder Routine der Datei ist (E2448; vor dem Attribut sichtbar, nicht durch eine gleichn' +
    'amige Konstante, einen Typ oder eine andere Deklaration verdeckt). Eigene Attribute dürfen mehrfach stehen; ein Typ Weak bzw. WeakAttribute in der Datei macht die Regel für diesen Namen still. Keine S' +
    'chnellkorrektur."',
    '    },',
    '    {',
    '      "id": "typeinfo-invalid",',
    '      "name": "TypeInfo oder Default mit unzulässigem Argument",',
    '      "description": "TypeInfo oder Default bekommt eine Variable statt eines Typs (wie E2133, E2537: Parameter, lokale, Inline- und Unit-Variablen, Felder, Properties, Result, for- und Ausnahmevariab' +
    'len), TypeInfo einen Typ ohne RTTI (Aufzählung mit festen Werten, Dateityp, Text/TextFile; E2134) oder Default einen Dateityp (E2538; Delphi 13 meldet zur Zuweisung zusätzlich E2015). Namen werden von' +
    ' innen nach außen aufgelöst; in with, in Helfern, in Methoden von Typen außerhalb der Datei, bei Deklarationen in anderen bedingten Zweigen und wenn Datei oder Index ein eigenes TypeInfo bzw. Default ' +
    'deklarieren, bleibt die Regel still. Korrektur: den deklarierten Typ der Variablen einsetzen."',
    '    },',
    '    {',
    '      "id": "missing-begin-end",',
    '      "name": "Bedingung oder Schleife ohne begin … end",',
    '      "description": "Der Rumpf von if … then, else, for, while oder with ist eine einzelne Anweisung ohne begin … end. Mit der Regel haben Bedingungen und Schleifen immer einen Block; eine später erg' +
    'änzte zweite Anweisung landet so nicht versehentlich außerhalb. else if bleibt erlaubt (das innere if braucht keinen eigenen Block); repeat … until, case … end, try … end und asm … end sind schon Blöc' +
    'ke. Eine leere Anweisung (if X then ;) meldet empty-statement. Rümpfe mit {$IFDEF} meldet die Regel nicht. Solange die Regel an ist, meldet redundant-begin-end nichts. Schnellkorrekturen: begin … end ' +
    'um die Anweisung setzen, für die ganze Methode oder für die ganze Datei, eingerückt nach den Formatierungseinstellungen; ein ; vor else wandert in den Block (kein E2153); mit format.elsePlacement \"sa' +
    'meLine\" steht else hinter dem neuen end (end else).",',
    '      "options": [',
    '        {',
    '          "name": "statements",',
    '          "description": "Geprüfte Anweisungen; case für die Zweige von case-Anweisungen ergänzen."',
    '        },',
    '        {',
    '          "name": "allowSingleLineExit",',
    '          "description": "Exit, Continue, Break und raise in derselben Zeile wie die Bedingung erlauben (if … then Exit;)."',
    '        },',
    '        {',
    '          "name": "allowSameLine",',
    '          "description": "Eine einzelne Anweisung in derselben Zeile wie Bedingung bzw. Schleifenkopf erlauben."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "inherited-constructor-after-try",',
    '      "name": "Geerbter Konstruktor erst im try-Block",',
    '      "description": "Ein Konstruktor betritt einen try-Block, bevor er den geerbten Konstruktor aufgerufen hat (wie H2505). Self ist dort noch nicht initialisiert; eine Exception im Block kann auf ha' +
    'lb erzeugte Felder treffen. Als geerbter Konstruktor gilt inherited ohne Namen, mit dem Namen des Konstruktors oder mit einem Namen, der mit Create beginnt. Zweige von {$IFDEF} werden getrennt geprüft' +
    '. Korrektur, wenn der Aufruf die erste Anweisung im try-Block ist: vor try ziehen."',
    '    },',
    '    {',
    '      "id": "variant-record-managed-field",',
    '      "name": "Verwalteter Typ im varianten Teil eines Records",',
    '      "description": "Im varianten Teil eines Records (case … of) steht ein String, ein dynamisches Array, ein Interface, ein Variant oder ein Record mit solchen Feldern (wie E2154), ein verwalteter R' +
    'ecord mit class operator Initialize oder Finalize (wie E2418) oder ein Typparameter ohne record-Einschränkung (wie E2569); ebenso hinter file of (wie E2155, E2417). Typen werden in der Datei und im In' +
    'dex aufgelöst; unbekannte bleiben still. Korrekturen: Feld vor case in den festen Teil verschieben, ShortString verwenden oder den Typparameter mit record einschränken."',
    '    },',
    '    {',
    '      "id": "guid-syntax-invalid",',
    '      "name": "GUID mit falscher Schreibweise",',
    '      "description": "Die GUID eines Interfaces oder einer typisierten TGUID-Konstante hat nicht die Form ''{8-4-4-4-12}'' (wie E2204): fehlende Klammern, falsche Zahl oder Länge der Blöcke, Zeichen, di' +
    'e keine Hexadezimalziffern sind, oft nach Hand-Bearbeitung. Geprüft werden nur einzelne Literale; Verkettungen und Konstanten bleiben still. Korrekturen: neue GUID erzeugen; fehlen nur die Klammern, s' +
    'ie ergänzen. Ergänzt interface-guid und duplicate-interface-guid."',
    '    },',
    '    {',
    '      "id": "untyped-pointer-refcount",',
    '      "name": "Untypisierter Zeiger umgeht die Referenzzählung",',
    '      "description": "Ein Interface wird über eine Typumwandlung nach Pointer zugewiesen (Pointer(FIntf) := P, wie W1070). Die Referenzzählung läuft dann nicht mit: das Objekt wird zu früh freigegeben' +
    ' oder nie. Die Regel meldet nur, wenn die Namensauflösung den Interface-Typ sicher kennt; Strings (string, AnsiString …) meldet sie ebenfalls, mit dem Zusatz „dcc meldet das nicht“, weil Delphi bei ih' +
    'nen nur unter NEXTGEN warnt. Felder mit [weak] oder [unsafe] bleiben still. Korrekturen für ein Interface-Feld dieser Datei mit Pointer(Y) oder nil rechts: das Feld mit [weak] bzw. [unsafe] auszeichne' +
    'n und ohne Pointer zuweisen."',
    '    },',
    '    {',
    '      "id": "type-too-large",',
    '      "name": "Typ überschreitet eine Größengrenze",',
    '      "description": "Ein statisches Array oder Record ist 2 GB groß oder größer (wie E2100), ebenso eine Instanz eines generischen Typs dieser Datei (wie E2543). Atlas rechnet eine untere Grenze aus ' +
    'den Deklarationen: Indexbereiche über konstante Ausdrücke, Konstanten und Aufzählungen der Datei, eingebaute Typen, Records aus dem Index; Unbekanntes zählt 0, gemeldet wird also nur sicher. Gemeldet ' +
    'wird nur der innerste Typ, der die Grenze überschreitet. E2419 (Records über 1 MB) gilt nur für Delphi für .NET und wird nicht gemeldet. Keine Korrektur; stattdessen ein dynamisches Array oder einen Z' +
    'eiger verwenden."',
    '    },',
    '    {',
    '      "id": "comparison-always-constant",',
    '      "name": "Vergleich immer wahr oder immer falsch",',
    '      "description": "Vergleich einer Variablen, eines Feldes, einer Property oder eines Funktionsergebnisses vom eingebauten Ganzzahltyp mit einer Konstanten außerhalb bzw. am Rand des Wertebereichs ' +
    '(wie W1021, W1022): Cardinal >= 0 ist immer wahr, Byte > 255 immer falsch. Ebenso case-Marken außerhalb des Bereichs des case-Ausdrucks (wie W1018); einzelne Marken, die auch mit anderem Vorzeichen ni' +
    'cht in die Breite des Typs passen, sind für dcc ein Fehler und meldet constant-expression-error (wie E1012). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit dem Vergleich über' +
    'setzt wird. NativeInt, LongInt und ihre vorzeichenlosen Gegenstücke gelten mit dem weitesten Bereich aller Plattformen; Teilbereichstypen meldet die Regel nicht. Length(…) < 0 und Length(…) >= 0 melde' +
    't sie ebenfalls, obwohl dcc dort nicht warnt; die Meldung sagt das dazu."',
    '    },',
    '    {',
    '      "id": "constant-initializer-mismatch",',
    '      "name": "Initialisierung einer Konstanten passt nicht",',
    '      "description": "Eine typisierte Konstante oder initialisierte Variable vom statischen Array-Typ hat mehr oder weniger Elemente als ihr Indexbereich (wie E2072), typisch nach einem neuen Wert in ' +
    'einer Aufzählung (array[TStatus] of string); geprüft je Dimension und auch für benannte Array-Typen der Datei. Ebenso Record-Konstanten, deren Felder in anderer Reihenfolge als deklariert stehen (wie ' +
    'E2083). Indexbereiche: Teilbereiche mit konstanten Grenzen, Aufzählungen ohne eigene Werte, Boolean, Byte, Char usw. Deklarationen mit bedingten Direktiven gelten als unsicher. Korrekturen: über einer' +
    ' Aufzählung fehlende Einträge an ihrer Stelle ergänzen bzw. überzählige entfernen (erkannt an Texten, Bezeichnern und Kommentaren mit dem Wertnamen; sonst hinten und als geschätzt benannt), neue Strin' +
    'gs mit dem Text aus dem Namen, andere Typen mit Standardwert und Kommentar {TODO Wert} (#667); über anderen Bereichen fehlende Einträge mit Platzhalter ergänzen; Felder in die Reihenfolge der Deklarat' +
    'ion bringen."',
    '    },',
    '    {',
    '      "id": "case-selector-not-ordinal",',
    '      "name": "case oder for ohne ordinalen Typ",',
    '      "description": "case über einen nicht ordinalen Ausdruck (wie E2001): Strings, Gleitkommazahlen, Klassen und Interfaces; for-Schleife mit nicht ordinaler Zählvariable (wie E2032); case-Marken un' +
    'd Array-Grenzen, die Variablen, Felder, Properties, Parameter oder typisierte Konstanten statt Konstanten sind (wie E2026). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der' +
    ' Anweisung übersetzt wird. Korrektur bei Strings mit lauter String-Literalen als Marken: case IndexStr(S, […]) of mit den Positionen als Marken, System.StrUtils kommt in die uses."',
    '    },',
    '    {',
    '      "id": "suspicious-string-pointer-cast",',
    '      "name": "Zeiger und Zeichenbreite eines Strings passen nicht zusammen",',
    '      "description": "PChar bzw. PWideChar auf einen AnsiString, RawByteString oder UTF8String und PAnsiChar auf einen string, UnicodeString oder WideString (wie W1044): Zeiger und Zeichenbreite passe' +
    'n nicht zusammen, typisch nach der Unicode-Umstellung; die API liest dann Datenmüll bzw. nur das erste Zeichen. Gemeldet wird nur bei sicher bekanntem Typ des Arguments, dessen Deklaration immer mit d' +
    'er Umwandlung übersetzt wird. string(PAnsiChar) wandelt korrekt um, ein Zeiger auf TBytes kann gewollt sein; beides meldet die Regel nicht. Korrekturen: eigene Variable mit passendem Stringtyp deklari' +
    'eren (PChar(Pfad) mit Pfad: AnsiString wird Pfad: string), string(…) bzw. AnsiString(…) um das Argument, passenden Zeigertyp verwenden."',
    '    },',
    '    {',
    '      "id": "string-conversion",',
    '      "name": "Umwandlung zwischen Unicode- und ANSI-Strings",',
    '      "description": "Implizite und ausdrückliche Umwandlungen zwischen string, UnicodeString oder WideString auf der einen und AnsiString, RawByteString oder UTF8String auf der anderen Seite, wie die' +
    ' Compilerwarnungen: implizit in string (wie W1057) bzw. in AnsiString mit möglichem Datenverlust (wie W1058) bei Zuweisungen, Inline-Variablen mit Typ und Argumenten für Wert- und const-Parameter von ' +
    'Routinen ohne Überladungen; ausdrückliche Umwandlungen string(A) (wie W1059) und AnsiString(S) (wie W1060); eine Stringkonstante mit Zeichen, die die ANSI-Codepage nicht kennt, an einen AnsiString (wi' +
    'e W1058 und W1062); ein WideChar in einem Mengenausdruck aus Zeichenliteralen wie C in [''0''..''9''] (wie W1050); ein Zeichen eines string direkt ändern (S[1] := ''x'', wie W1068). Wie bei dcc meldet die R' +
    'egel W1059, W1060 und W1068 nur nach {$WARN EXPLICIT_STRING_CAST ON}, {$WARN EXPLICIT_STRING_CAST_LOSS ON} bzw. {$WARN IMMUTABLE_STRINGS ON}; {$WARN … OFF} und {$WARNINGS OFF} schalten sie ab ihrer St' +
    'elle ab, {$WARN … ERROR} meldet einen Fehler. Gemeldet wird nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse und typisierte Konstanten der eingebauten Stri' +
    'ngtypen aus System, auch über einen einfachen Alias) und ihre Deklarationen immer mit der Anweisung übersetzt werden. Still bleiben: Verkettungen, Umwandlungen als Quelle, Umwandlungen zwischen zwei A' +
    'NSI-Typen (AnsiString, RawByteString, UTF8String; dcc wandelt nach Codepage um), eigene Stringtypen wie type AnsiString(28591), {$H-} und Delphi vor 2009. W1062 hängt von der ANSI-Codepage des überset' +
    'zenden Rechners ab (Option ansiCodePage, Vorgabe 1252; 0 schaltet diese Prüfung ab); gemeldet werden nur Zeichen, die Windows auch nicht ersatzweise abbildet: Hebräisch bis Thai, Hangul, Kana und CJK,' +
    ' Symbole und Dingbats U+2600–U+27BF und Zeichen außerhalb der BMP (Emoji). Projektoptionen der .dproj (DCC_IMPLICIT_STRING_CAST = false, true oder error usw.) gelten wie bei dcc. Korrekturen: ausdrück' +
    'lich umwandeln (string(A), AnsiString(S)); CharInSet verwenden und System.SysUtils in uses eintragen.",',
    '      "options": [',
    '        {',
    '          "name": "ansiCodePage",',
    '          "description": "ANSI-Codepage des Rechners, der übersetzt; Zeichen, die ihr sicher fehlen, meldet die Regel wie W1062, wenn sie an einen AnsiString gehen. Bekannt ist nur 1252; 0 oder ein an' +
    'derer Wert schaltet diese Prüfung ab."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unsafe-code",',
    '      "name": "Unsicherer Code",',
    '      "description": "Code, den dcc seit Delphi für .NET als unsicher meldet: der @-Operator auf eine Variable, ein Feld oder einen Parameter (wie W1047) und die Umwandlung eines untypisierten Pointer' +
    ' in eine Klasse, TObject(P) bzw. TKunde(P) (wie W1048). dcc schaltet diese Warnungen ab Werk ab; die Regel meldet nur, wo sie wie bei dcc an sind: {$WARN UNSAFE_CODE ON} bzw. {$WARN UNSAFE_CAST ON} vo' +
    'r der Stelle oder DCC_UNSAFE_CODE bzw. DCC_UNSAFE_CAST = true in der .dproj; ERROR macht den Treffer zum Fehler, OFF und {$WARNINGS OFF} halten ihn still. @ auf Routinen und Methoden, typisierte Zeige' +
    'r, Umwandlungen als Argument (TObject(Pointer(I))) und Interfaces bleiben still. Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der Stelle übersetzt wird."',
    '    },',
    '    {',
    '      "id": "inaccessible-member",',
    '      "name": "Zugriff auf ein nicht sichtbares Mitglied",',
    '      "description": "Zugriff A.B auf ein Mitglied, das an der Stelle nicht sichtbar ist: private bzw. strict private einer anderen Unit oder Klasse (wie E2361), protected bzw. strict protected außerh' +
    'alb der deklarierenden Unit und ihrer Nachfahren (wie E2362, E2389). In einer Klassenmethode oder statischen Methode sind Instanzfelder, -methoden und -Properties der Klasse nicht erreichbar (wie E212' +
    '4). Eine Property, die auf ein private-Mitglied eines Vorfahren derselben Unit verweist, meldet die Regel als Warnung (wie W1045). Gemeldet wird nur, wenn die Namensauflösung den Empfänger und seinen ' +
    'Typ sicher kennt und das Mitglied erst ohne Rücksicht auf die Sichtbarkeit findet; protected-Mitglieder bleiben über eine Klasse der eigenen Unit sichtbar (TZugang(Control).Click). Ein privater Klasse' +
    'nkonstruktor verdeckt kein geerbtes Create, und eine class-Überladung einer Methode bleibt aus einer Klassenmethode erreichbar. protected-Mitglieder über einen generischen Empfänger (TKnoten<T>) übers' +
    'etzt dcc aus generischem Code auch in anderen Units (Spring4D); aus nicht generischem Code meldet dcc E2362. Deklarationen in bedingten Zweigen, Methoden von Helfern und verschachtelten Typen bleiben ' +
    'still."',
    '    },',
    '    {',
    '      "id": "unused-private-member",',
    '      "name": "Privates Mitglied wird nie verwendet",',
    '      "description": "Ein private- oder strict-private-Feld, eine Methode, Konstante oder Property kommt in der Unit nirgends vor (wie H2219, das der Compiler nur für Methoden meldet; Felder ebenso, a' +
    'ußer includeFields ist aus). Jedes Vorkommen des Namens als Bezeichner zählt als Verwendung, auch in inaktiven bedingten Zweigen und hinter read/write; Deklarationen und Methodenköpfe zählen nicht. Au' +
    'sgenommen: Methoden mit message, virtual, dynamic, override oder abstract, Methoden von Typen, die Interfaces umsetzen, Konstruktoren und Destruktoren, Mitglieder mit Attributen (RTTI), Namen aus der ' +
    'Formulardatei und Units mit Include-Dateien. Korrektur: Deklaration (samt ///-Doku) und den Rumpf einer Methode entfernen; nicht, wenn sich mehrere Mitglieder die Deklaration teilen oder die Methode ü' +
    'berladen ist.",',
    '      "options": [',
    '        {',
    '          "name": "includeFields",',
    '          "description": "Auch nie verwendete private Felder melden (der Compiler meldet nur Methoden)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unused-public-member",',
    '      "name": "Öffentliches Mitglied wird im Projekt nie verwendet",',
    '      "description": "Eine public- oder published-Methode, -Konstante oder -Property (wahlweise auch protected-Mitglieder, Felder und Klassenvariablen) bzw. eine Routine, Konstante, ein Typ oder eine ' +
    'globale Variable im interface-Abschnitt einer Unit (Option unitKinds) wird in den Projekten der Projektgruppe nirgends verwendet. Die Suche läuft projektweit über den Symbolindex: Nur Dateien, deren V' +
    'erwendungen im Index den Namen enthalten, werden gelesen, und jedes Vorkommen wird über die Namensauflösung zugeordnet; ein Vorkommen, das sich nicht auflösen lässt, zählt als Verwendung. Namen in For' +
    'mulardateien (.dfm/.fmx) und in String-Literalen zählen als Verwendung. Gelten als verwendet: Interface-Umsetzungen und Mitglieder von Interfaces, Methoden mit virtual, dynamic, override, abstract ode' +
    'r message, Konstruktoren, Destruktoren, Operatoren, Enumeratoren, Default-Properties, implements, Mitglieder mit Attributen, published-Mitglieder von TPersistent-Nachfahren (Streaming), von Klassen au' +
    's RegisterComponents, RegisterClass oder RegisterClasses und von Testklassen, published-Methoden, solange eine Formulardatei nicht lesbar ist, Property-Zugriffsmethoden, exportierte Routinen, Klassenh' +
    'elfer und Mitglieder von Klassen mit unbekanntem Vorfahren. Still, solange Projekte laden oder der Index unvollständig ist, wenn eine Datei nicht lesbar ist, bei Units mit Include-Dateien und bei Unit' +
    's von Packages oder Bibliotheken (Nutzer außerhalb des Projekts), außer projectKinds lässt sie zu. Bei Typen zählen Vorkommen in der eigenen Deklaration und in den Rümpfen der eigenen Methoden (samt K' +
    'opf TTyp.Name) nicht; Typen aus RegisterComponents, RegisterClass oder RegisterClasses gelten als verwendet, bei Attributklassen (XyzAttribute) zählt auch die Kurzform [Xyz]. deadCode.keepAttributes u' +
    'nd deadCode.keepPatterns aus den Einstellungen gelten zusätzlich zu keepAttributes und keepPatterns. Korrektur: als bewusst öffentlich markieren (lsp-ignore-Kommentar).",',
    '      "options": [',
    '        {',
    '          "name": "visibilities",',
    '          "description": "Geprüfte Sichtbarkeiten: public, published, protected."',
    '        },',
    '        {',
    '          "name": "memberKinds",',
    '          "description": "Geprüfte Arten von Typmitgliedern: method, constant, property, field, classVar. Deklarationen auf Unit-Ebene richten sich nach unitKinds."',
    '        },',
    '        {',
    '          "name": "projectKinds",',
    '          "description": "Projektarten, deren Units geprüft werden: application, package, library. Packages und Bibliotheken haben Nutzer außerhalb der Projektgruppe und sind deshalb standardmäßig aus' +
    '."',
    '        },',
    '        {',
    '          "name": "unitLevel",',
    '          "description": "Auch Deklarationen des interface-Abschnitts einer Unit prüfen (Arten aus unitKinds)."',
    '        },',
    '        {',
    '          "name": "unitKinds",',
    '          "description": "Mit unitLevel geprüfte Arten auf Unit-Ebene: routine, constant, type, variable. Helfer werden nie gemeldet (sie werden über den erweiterten Typ verwendet)."',
    '        },',
    '        {',
    '          "name": "scope",',
    '          "description": "Wo nach Verwendungen gesucht wird: projectGroup (alle Projekte der Gruppe) oder project (nur die Projekte der Datei)."',
    '        },',
    '        {',
    '          "name": "testsCountAsUse",',
    '          "description": "Verwendungen in Testprojekten zählen; ist es aus, wird ein Mitglied, das nur Tests verwenden, als solches gemeldet."',
    '        },',
    '        {',
    '          "name": "stringLiteralsCountAsUse",',
    '          "description": "Der Name als String-Literal (''Name'') zählt als Verwendung (RTTI, MethodAddress, Skripte)."',
    '        },',
    '        {',
    '          "name": "keepAttributes",',
    '          "description": "Attribute am Mitglied oder seinem Typ, die es als verwendet markieren, z. B. \"Keep\" oder \"Api\"."',
    '        },',
    '        {',
    '          "name": "keepPatterns",',
    '          "description": "Namensmuster (* und ?) für Mitglieder, die immer als verwendet gelten, z. B. \"TPlugin.*\" oder \"*Callback\"."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unused-declaration",',
    '      "name": "Deklaration im implementation-Abschnitt wird nie verwendet",',
    '      "description": "Eine Routine, ein Typ, eine Konstante oder eine globale Variable aus dem implementation-Abschnitt einer Unit (bzw. aus einem Programm oder einer DLL) wird in der Unit nirgends ve' +
    'rwendet; der Compiler meldet das nicht. Jedes Vorkommen des Namens als Bezeichner zählt als Verwendung, auch in inaktiven Zweigen; nicht zählen die Deklarationen selbst (auch forward), Vorkommen im ei' +
    'genen Rumpf (Rekursion) und bei Typen Vorkommen in der eigenen Deklaration und in den Rümpfen der eigenen Methoden samt Kopf TTyp.Name. Bei Attributklassen (XyzAttribute) zählt auch die Kurzform [Xyz]' +
    '. Gelten als verwendet (Dienst, den auch unused-public-member nutzt): exportierte Routinen, Deklarationen mit Attributen, Namen aus deadCode.keepPatterns, Typen mit einem Attribut aus deadCode.keepAtt' +
    'ributes und Namen aus der Formulardatei. Rümpfe von Routinen des interface-Abschnitts prüft unused-public-member. Still bei Units mit Include-Dateien. Korrektur: als bewusst vorhanden markieren (lsp-i' +
    'gnore-Kommentar)."',
    '    },',
    '    {',
    '      "id": "unused-unit",',
    '      "name": "Unit wird von keiner anderen Unit verwendet",',
    '      "description": "Eine Unit einer Anwendung verwendet keine andere Unit des Uses-Graphen: Höchstens Programme nennen sie im uses, und sie verwenden außerhalb ihres uses keinen ihrer Bezeichner (Ap' +
    'plication.CreateForm(TForm1, Form1) zählt als Verwendung). Units mit initialization- oder finalization-Abschnitt (Registrierungen, Seiteneffekte beim Start) gelten als verwendet, ebenso Units mit eine' +
    'r Klasse [TestFixture], die DUnitX per RTTI findet. Konfidenz mittel: Code außerhalb der Projektgruppe, Skripte oder zur Laufzeit geladene Packages können die Unit trotzdem nutzen. Still bei Units von' +
    ' Packages und DLLs (Nutzer außerhalb der Gruppe), solange projectKinds sie nicht erlaubt, ohne Projekte, solange Projekte laden oder der Index unvollständig ist, und für Units, die der Uses-Graph nich' +
    't kennt. Gemeldet am Unit-Namen im Kopf.",',
    '      "options": [',
    '        {',
    '          "name": "projectKinds",',
    '          "description": "Projektarten, deren Units geprüft werden: application, package, library."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unused-uses",',
    '      "name": "Ungenutzte Unit im uses",',
    '      "description": "Aus der Unit eines uses-Eintrags wird nichts verwendet: Kein Bezeichner außerhalb der uses-Listen gleicht einem ihrer interface-Symbole (auch Mitgliedern) oder dem letzten Teil i' +
    'hres Namens. Dieselbe Analyse wie die abgeblendeten uses-Einträge im Editor (#621): Units, die der Index nicht kennt, Units mit initialization- oder finalization-Abschnitt, Units aus usesKeep und Eint' +
    'räge in inaktiven {$IFDEF}-Zweigen bleiben. Konfidenz hoch. Sichere Korrektur: den Eintrag entfernen (mit seinem Komma; der einzige Eintrag entfernt das ganze uses), auch als Sammelkorrektur mit --fix' +
    ' unused-uses. Still im Editor, wo dieselben Einträge abgeblendet erscheinen, ohne Symbolindex (--no-index) und bei Syntaxfehlern."',
    '    },',
    '    {',
    '      "id": "message-method-invalid",',
    '      "name": "message-Methode falsch deklariert",',
    '      "description": "Eine message-Prozedur einer Klasse hat nicht genau einen var-Parameter (wie E2138; der Typ wird nicht geprüft, ein untypisierter var-Parameter ist in Ordnung), ihre Nachrichtennu' +
    'mmer ist kleiner als 1 (wie E2139) oder eine frühere message-Methode derselben Klasse behandelt schon dieselbe Nummer (wie E2140, meist nach Kopieren). Nummern gelten als gleich, wenn ihre Werte bekan' +
    'nt sind (Zahlen, Konstanten aus dem Index) oder die Ausdrücke gleich lauten. Methoden in sich ausschließenden {$IF}-Zweigen sind nicht doppelt; dieselbe Nummer in einem Nachfahren überschreibt den Han' +
    'dler und ist erlaubt. Korrektur für E2138: einen einzelnen Parameter zu var machen, sonst die Liste durch (var Msg: TMessage) ersetzen; der Rumpf in derselben Datei wird mit angepasst."',
    '    },',
    '    {',
    '      "id": "interface-declaration-invalid",',
    '      "name": "Unzulässige Deklaration in einem Interface",',
    '      "description": "Ein Interface deklariert etwas, das Interfaces nicht haben dürfen: Felder (wie E2209), Sichtbarkeitsabschnitte oder Methodendirektiven wie virtual, dynamic, abstract, override, m' +
    'essage oder reintroduce (wie E2210), die Property-Klauseln stored, nodefault oder default mit Wert (wie E2207; default; hinter einer Array-Property ist erlaubt) oder eine Property, die ein Vorfahr-Int' +
    'erface schon deklariert, ohne Typ erneut aufgeführt (wie E2206; eine Neudeklaration mit Typ übersetzt dcc, auch mit geerbten Accessoren). Ebenso gemeldet werden eine Klasse, ein Record oder eine Aufzä' +
    'hlung als Vorfahr eines Interfaces oder in der Interface-Liste einer Klasse (wie E2205) und dasselbe Interface zweimal in dieser Liste (wie E2208). Typen werden über die uses-Klauseln aufgelöst; Alias' +
    'e, unbekannte Typen, dispinterface und Deklarationen in bedingten Zweigen bleiben still."',
    '    },',
    '    {',
    '      "id": "implements-clause-invalid",',
    '      "name": "implements-Klausel unzulässig",',
    '      "description": "Eine Delegation mit implements verletzt eine ihrer festen Regeln: implements nur in Klassen (wie E2258), nur an Properties mit Klassen- oder Interface-Typ (wie E2259; gemeldet fü' +
    'r eingebaute Typen, Records und Aufzählungen), nicht zusammen mit index (wie E2260), nur an lesbaren Properties (wie E2261), der Getter ohne andere Aufrufkonvention als register (wie E2262) und nicht ' +
    'dynamic oder message (wie E2263; Delphi 13 meldet zusätzlich E2148), jedes Interface nur über eine Property (wie E2257) und keine Methodenzuordnung für ein so umgesetztes Interface (wie E2264). Typen ' +
    'werden über die uses-Klauseln aufgelöst; unbekannte Typen, Aliase und Properties in bedingten Zweigen bleiben still."',
    '    },',
    '    {',
    '      "id": "calling-convention-required",',
    '      "name": "Aufrufkonvention passt nicht",',
    '      "description": "Der Compiler schreibt hier die Aufrufkonvention vor: Konstruktoren und Destruktoren einer Klasse nur mit register (wie E2236), Getter und Setter von published-Properties ebenso (' +
    'wie E2270) und varargs nur mit cdecl (wie E2277 bei external-Routinen, sonst E2591); ohne external ist varargs unter Win32 gar nicht erlaubt (wie E2277), was die Regel nur bei bekannter Plattform meld' +
    'et. Ein ausdrückliches register ist in Ordnung; Klassenkonstruktoren, Accessoren außerhalb von published-Abschnitten und geerbte Accessoren bleiben still. Korrektur: die Konvention in der Deklaration ' +
    'und im Rumpf derselben Datei entfernen bzw. bei varargs cdecl setzen."',
    '    },',
    '    {',
    '      "id": "automation-invalid",',
    '      "name": "OLE-Automation falsch deklariert oder aufgerufen",',
    '      "description": "Deklarationen, die der Compiler im Abschnitt automated einer Klasse ablehnt: Felder (wie E2175), Konstruktoren und Destruktoren (wie E2177), dynamic- und message-Methoden (wie E2' +
    '178), andere Aufrufkonventionen als register (wie E2179), dieselbe dispid zweimal in einer Klasse (wie E2180), eine Property, die ohne Typ neu deklariert wird (wie E2181), index, stored, default und n' +
    'odefault an Properties (wie E2182), read oder write auf ein Feld der Klasse (wie E2096), eine dispid an einer override-Methode (wie E2185) sowie Records, Zeiger und Mengen als Typ von Parametern, Erge' +
    'bnissen und Properties (wie E2176). Eine dispid an einer Methode außerhalb von automated meldet die Regel wie Delphi 13 als E2185 (dokumentiert ist E2183). Aufrufe über Variant oder OleVariant (V.Oeff' +
    'nen(...), auch V.Dokument.Oeffnen(...)): ein Record ohne Operatoren oder ein Zeiger als Argument (wie E2160 bei OleVariant, wie E2281 bei Variant) und ein unbenanntes Argument nach einem benannten (wi' +
    'e E2166). Mitglieder in bedingten Zweigen und Typen, die die Namensauflösung nicht sicher kennt, bleiben still. Dass automated selbst veraltet ist, meldet deprecated-symbol."',
    '    },',
    '    {',
    '      "id": "dispinterface-invalid",',
    '      "name": "dispinterface-Deklaration unzulässig",',
    '      "description": "Ein dispinterface verletzt eine seiner festen Regeln: kein Vorfahr in Klammern (wie E2228), eine GUID ist Pflicht (wie E2229), Methoden tragen keine Direktiven außer dispid und d' +
    'en Hinweisen deprecated, platform, library und experimental (wie E2230; gemeldet werden Aufrufkonventionen und Bindungsdirektiven wie virtual, overload bleibt still) und Properties kein read oder writ' +
    'e (wie E2231; stattdessen readonly, writeonly oder dispid). Vorwärtsdeklarationen und Deklarationen in bedingten Zweigen bleiben still. Korrekturen: Vorfahren entfernen, GUID einfügen, Direktive entfe' +
    'rnen."',
    '    },',
    '    {',
    '      "id": "abstract-declaration-invalid",',
    '      "name": "abstract, final oder static falsch kombiniert",',
    '      "description": "Eine Methodendirektive, die der Compiler ablehnt: abstract ohne virtual, dynamic oder override (wie E2167), ein Rumpf im implementation-Teil zu einer abstrakten Methode (wie E213' +
    '6), final an einer nicht virtuellen Methode (wie E2351), abstract zusammen mit final (wie E2371), eine Klasse abstract sealed (wie E2540), eine abstrakte Methode in einer sealed-Klasse (wie E2383, E25' +
    '40) oder eine sealed-Klasse, die eine geerbte abstrakte Methode offen lässt (wie E2539, Vorfahren über den Symbolindex) oder static an einer Instanzmethode bzw. einer virtuellen Klassenmethode (wie E2' +
    '376). Ein Rumpf zählt nur dann als Rumpf einer abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben Klasse mit ihm übersetzt wird (Überladungen, {$IFDEF}-Zweige). Korrekturen:' +
    ' virtual; vor abstract einfügen, Rumpf entfernen."',
    '    },',
    '    {',
    '      "id": "declaration-invalid",',
    '      "name": "Deklaration, die der Compiler ablehnt",',
    '      "description": "Eine Deklaration, die Delphi schon wegen ihrer Form ablehnt: packed vor einem anderen Typ als array, record, object, class, set, file oder string (wie E2006), eine Routine mit Er' +
    'gebnistyp file (wie E2024), ein virtueller Konstruktor in einem object-Typ (wie E2062), eine Property ohne read, write und index in einem Interface, das kein dispinterface ist, oder in einem automated' +
    '-Abschnitt (wie E2128) oder zwei Konstruktoren mit verschiedenen Namen und denselben Parametertypen, wenn das Projekt C++-Ausgaben erzeugt (DCC_CBuilderOutput oder Schalter -J in der .dproj, wie W1029' +
    '). Neudeklarationen von Properties ohne Typ bleiben still. Keine Korrektur: Die richtige hängt von der Absicht ab."',
    '    },',
    '    {',
    '      "id": "unsatisfied-forward",',
    '      "name": "Vorwärtsdeklaration nie aufgelöst",',
    '      "description": "Eine Routine aus dem interface-Teil oder mit forward hat keinen Rumpf (wie E2065), oder eine Vorwärtsdeklaration TFoo = class; bzw. IFoo = interface; wird im selben type-Abschnit' +
    't nie vollständig deklariert (wie E2086, E2420). Ein Record, der sich selbst als Feld enthält, und eine Klasse oder ein Interface, die einen erst vorwärts deklarierten Typ als Vorfahr oder in der Inte' +
    'rface-Liste nutzen, verwenden ebenfalls einen unvollständigen Typ (wie E2086). Methoden prüft declared-not-implemented. Ein Rumpf passt, wenn er gleich heißt; bei overload muss auch die Zahl der Param' +
    'eter stimmen. Ein external im implementation-Teil zählt als Rumpf. Deklarationen in einem {$IFDEF}-Zweig bleiben unbeachtet; mit Include-Dateien prüft die Regel keine Routinen. Korrektur: leeren Rumpf' +
    ' vor initialization bzw. dem abschließenden end. anlegen."',
    '    },',
    '    {',
    '      "id": "member-hides-ancestor",',
    '      "name": "Member verdeckt einen Member des Vorfahren",',
    '      "description": "Eine Property heißt wie ein Feld eines Vorfahren (wie W1009), ein Feld wie ein Feld oder eine Property eines Vorfahren oder eine nicht virtuelle Methode hat Namen und Parameter e' +
    'iner nicht virtuellen Methode eines Vorfahren (die beiden letzten ohne Code: Delphi 13 übersetzt sie still). Code, der über den Vorfahrtyp zugreift, sieht weiter den alten Member. Virtuelle Methoden m' +
    'eldet hides-virtual, lokale Namen shadowed-name. Neu veröffentlichte Properties (property Caption;), Properties mit neuem Typ über einer Property des Vorfahren, overload, reintroduce, Konstruktoren un' +
    'd Klassenmethoden bleiben unbeanstandet. Member, die der Nachfahre nicht sieht (private einer anderen Unit, strict private mit ignoreStrictPrivate), zählen nicht; Vorfahren kommen aus der Datei und de' +
    'm Symbolindex. Korrektur für Felder und Properties: den Member in der Klassendeklaration und in den Rümpfen ihrer Methoden in dieser Unit umbenennen (aus FName wird FKundeName).",',
    '      "options": [',
    '        {',
    '          "name": "ignoreStrictPrivate",',
    '          "description": "Verdeckte strict private Member des Vorfahren nicht melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "published-type-invalid",',
    '      "name": "Unzulässiges Mitglied im published-Abschnitt",',
    '      "description": "Ein Mitglied hinter einem ausdrücklichen published, das der Compiler ablehnt: eine Property vom Typ statisches Array, Zeiger oder Prozedurtyp ohne of object (wie E2188; Records u' +
    'nd dynamische Arrays übersetzt dcc), vom Typ Real48 (wie E2186) oder eine Menge über 4 Byte (wie E2187), ein Feld, das weder Klasse noch Interface ist (wie E2217), mehr als eine published-Überladung (' +
    'wie E2266), eine Klassen-Property (wie E2545) oder ein Name mit Zeichen außerhalb von ASCII (wie E2452). Typen löst die Regel über die Datei und den Index auf und verfolgt Aliase; Typparameter, unbeka' +
    'nnte Typen und Abschnitte, deren published in einem anderen Zweig der bedingten Übersetzung steht als das Mitglied, bleiben still. Den Abschnitt ohne Sichtbarkeitsangabe prüft sie nicht, weil der Comp' +
    'iler solche Mitglieder dort still zu public herabstuft. Korrektur: das Mitglied in den public-Abschnitt verschieben."',
    '    },',
    '    {',
    '      "id": "override-case-mismatch",',
    '      "name": "Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab",',
    '      "description": "Eine überschreibende Methode schreibt ihren Namen anders als der Vorfahr (destructor destroy, wie H2365) oder ist weniger sichtbar als die überschriebene Methode (wie H2269, nur ' +
    'für Klassen im interface-Teil; verglichen werden die Stufen privat, geschützt, öffentlich), ein Getter oder Setter heißt Get<Property> bzw. Set<Property>, ist aber anders geschrieben, oder eine inline' +
    '-Methode greift auf ein Mitglied zu, das weniger sichtbar ist als sie selbst (diese beiden ohne Code: Delphi 13 meldet dort weder H2367 noch H2440). Wichtig für C++Builder-Nutzer der Units und für ein' +
    'heitlichen Code. Die Docwiki führt H2269 und H2367 als X2269 und X2367, weil sich ihre Stufe umstellen lässt; dcc meldet sie standardmäßig als Hinweis. H2368 und H2369 deckt die Regel nicht ab, weil n' +
    'icht dokumentiert ist, wann dcc sie meldet. Standardmäßig aus; in atlas.json einschalten. Korrekturen: Schreibweise vom Vorfahr übernehmen, Zugriffsmethode umbenennen."',
    '    },',
    '    {',
    '      "id": "default-property-invalid",',
    '      "name": "default-Property falsch deklariert oder fehlt",',
    '      "description": "default; hinter einer Property ohne Indexparameter (wie E2132), eine zweite default-Property derselben Klasse mit anderem Namen oder denselben Indextypen (wie E2131; Überladung ü' +
    'ber den Indextyp unter demselben Namen ist erlaubt) oder Obj[I] auf einer Klasse, die in ihrer ganzen Vorfahrenkette keine default-Property hat (wie E2149). Den Typ von Obj ermittelt die Namensauflösu' +
    'ng; nicht auflösbare Typen, abgebrochene Vorfahrenketten und Klassen mit einem Class-Helper in der Unit bleiben still. Neudeklarationen ohne Typ (property Items; default;) übernehmen den Index des Vor' +
    'fahren und werden nicht geprüft."',
    '    },',
    '    {',
    '      "id": "property-redeclaration-invalid",',
    '      "name": "Neu deklarierte Property fehlt im Vorfahren",',
    '      "description": "Eine Neudeklaration ohne Typ wie property Caption; (um Sichtbarkeit oder Standardwert zu ändern) nennt eine Property, die kein Vorfahr hat (wie E2147), oder die Property des Vorf' +
    'ahren ist von hier aus nicht erreichbar: strict private oder private in einer anderen Unit (wie E2233). Gemeldet nur, wenn die ganze Vorfahrenkette bekannt ist; ein gleichnamiges Feld oder eine Method' +
    'e und Deklarationen in inaktiven Zweigen bleiben still. Korrektur: den ähnlichsten Property-Namen der Vorfahren verwenden."',
    '    },',
    '    {',
    '      "id": "inline-not-expanded",',
    '      "name": "Inline-Funktion wird nicht eingebettet",',
    '      "description": "Aufruf einer inline-Routine aus einer anderen Unit, die der Compiler nicht einbettet: Ihr Rumpf braucht eine Unit, die hier in uses fehlt (wie H2443, typisch System.Generics.Coll' +
    'ections bei TJSONObject.Count), die aufrufende Routine ist selbst inline und die Unit der gerufenen steht nur im uses des implementation-Teils (wie H2445), oder die Unit der gerufenen Routine verwende' +
    't diese Unit direkt (wie H2456) bzw. über andere Units (wie H2457; nur, wenn der Rumpf auf mehr als eingebaute Typen, Intrinsics und System verweist). Geprüft werden Aufrufe, Properties mit inline-Get' +
    'ter bzw. -Setter und for-in (GetEnumerator, MoveNext, Current). Der Index merkt sich, worauf jeder inline-Rumpf verweist; die Regel meldet nur, was sie sicher auflöst (unbekannte Verweise und geerbte ' +
    'Mitglieder aus anderen Units bleiben stumm; ein Alias einer Deklaration aus System wie tkRecord in System.TypInfo braucht dessen Unit nicht). Zugriffe auf private- oder strict private-Mitglieder melde' +
    't sie nicht: Delphi 13 bettet solche Aufrufe ein. Mit {$INLINE OFF} in der Datei schweigt sie. Korrektur: die fehlenden Units in das uses des Abschnitts aufnehmen."',
    '    },',
    '    {',
    '      "id": "compiler-hints",',
    '      "name": "Compilerhinweis ohne eigene Regel",',
    '      "description": "Hinweise und Warnungen des Compilers, die zu keiner anderen Regel gehören. published in einer Klasse ohne RTTI: Der Compiler schaltet für sie {$M+} ein (wie W1055); gemeldet einm' +
    'al je Klasse am ersten Mitglied hinter dem ersten ausdrücklichen published, still bei {$M+} oder {$TYPEINFO ON} an der Deklaration, bei einem Vorfahren mit RTTI (bekannte Nachfahren von TPersistent, {' +
    '$M+} an seiner Deklaration oder eigene published-Mitglieder) und nach {$WARN TYPEINFO_IMPLICITLY_ADDED OFF} oder {$WARNINGS OFF}; ein Vorfahr, dessen Kette nicht bis TObject bekannt ist oder dessen Da' +
    'tei sich nicht lesen lässt, hält die Regel still, ebenso generische und verschachtelte Klassen. Initialize oder Finalize mit einer Variablen eines eingebauten Typs ohne verwaltete Teile wie Integer, D' +
    'ouble oder Boolean, auch über Aliase (wie H2243), oder mit einer Variablen eines Zeigers auf einen verwalteten Typ wie PString oder PVariant, wo wohl P^ gemeint war (wie H2244); nur Aufrufe mit einem ' +
    'einfachen Bezeichner, dessen Typ sicher bekannt ist, still nach {$HINTS OFF} und wenn Initialize bzw. Finalize eine eigene Routine oder ein Mitglied meinen kann (with, Methode einer Klasse mit unbekan' +
    'ntem Vorfahren)."',
    '    },',
    '    {',
    '      "id": "directive-typo",',
    '      "name": "Unbekannte Direktive (Tippfehler)",',
    '      "description": "An der Stelle einer Direktive steht ein Wort, das keine ist: nach dem '';'' eines Routinen- oder Methodenkopfs (overide;, virutal;, overlaod;, stdcal;, reintroduces;) oder nach ein' +
    'er Property, wo nur default erlaubt ist (defualt;). Der Compiler bricht dort ab (wie E2070). Die Meldung schlägt die ähnlichste Direktive vor, wenn höchstens zwei Zeichen abweichen. Still in {$IF}-Zwe' +
    'igen, die FPC abfragen; FPC kennt weitere Direktiven wie nostackframe. Korrektur: durch die vorgeschlagene Direktive ersetzen."',
    '    },',
    '    {',
    '      "id": "ui-call-in-console-or-service",',
    '      "name": "Dialog in Konsolenprogramm oder Dienst",',
    '      "description": "ShowMessage, ShowMessageFmt, MessageDlg, TaskMessageDlg, InputBox, InputQuery, Application.MessageBox oder TDialogService in einem Programm mit {$APPTYPE CONSOLE} (oder DCC_Conso' +
    'leTarget in der .dproj), in einem Windows-Dienst oder in einer DLL ohne Formulare. Im Dienst blockiert der Dialog unsichtbar; ein Konsolenprogramm wartet auf einen Klick, den niemand sieht, wenn es un' +
    'beaufsichtigt läuft. Als Dienst gilt eine Unit mit einer Klasse, die von TService erbt, oder jede Unit eines Projekts, dessen .dpr Vcl.SvcMgr ohne Vcl.Forms einbindet. Eine DLL ohne Formulare ist eine' +
    ' library, deren .dpr kein Formular aufführt und Vcl.Forms nicht einbindet; dort meldet die Regel mit mittlerer Konfidenz, weil erst der Host entscheidet, ob es eine Oberfläche gibt. Units mit Formular' +
    'datei, Aufrufe unter if IsConsole und gleichnamige Routinen der Unit bleiben still. Gegenstück zu writeln-in-gui-app. Konfidenz hoch. Keine Schnellkorrektur: die Meldung protokollieren statt anzeigen.' +
    '"',
    '    },',
    '    {',
    '      "id": "load-without-encoding",',
    '      "name": "Text laden oder speichern ohne Kodierung",',
    '      "description": "LoadFromFile, SaveToFile, LoadFromStream oder SaveToStream einer TStrings (TStringList, Memo.Lines, ListBox.Items, Query.SQL) sowie TFile.ReadAllText und TFile.ReadAllLines ohne ' +
    'Kodierung: Eine Datei ohne BOM wird mit der ANSI-Codepage des Rechners gelesen, SaveToFile schreibt ANSI, und Umlaute gehen zwischen Rechnern verloren. Der Empfänger muss eine deklarierte Stringliste ' +
    'oder eine Property Lines, Items, SQL oder Strings sein; Bilder, Streams und Datenmengen bleiben still. Ebenso still, wenn die Liste irgendwo in der Unit DefaultEncoding setzt oder in derselben Routine' +
    ' vorher mit Kodierung geladen wurde (SaveToFile behält diese Kodierung). TFile.WriteAllText, TStreamReader und TStreamWriter nehmen ohne Angabe schon UTF-8 und werden nicht gemeldet. Konfidenz mittel.' +
    ' Schnellkorrektur: TEncoding.UTF8 (Option defaultEncoding) als letztes Argument und System.SysUtils im uses ergänzen.",',
    '      "options": [',
    '        {',
    '          "name": "defaultEncoding",',
    '          "description": "Property von TEncoding, die die Schnellkorrektur einsetzt: UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "registry-hklm-write",',
    '      "name": "Schreiben nach HKEY_LOCAL_MACHINE",',
    '      "description": "RootKey := HKEY_LOCAL_MACHINE auf einer TRegistry, danach in derselben Routine ein schreibender Zugriff auf dasselbe Objekt: OpenKey(…, True), CreateKey, Write…, DeleteKey, Delet' +
    'eValue, RenameValue, MoveKey, SaveKey oder RestoreKey. Ohne Administratorrechte schlägt das fehl oder landet still in der Virtualisierung der Registry. Für Benutzereinstellungen HKEY_CURRENT_USER verw' +
    'enden; Installer-Code über exclude ausnehmen. Lesen (OpenKeyReadOnly, Read…, OpenKey(…, False)), ein anderer RootKey vor dem Schreiben und Schreiben im anderen Zweig von {$IFDEF} bleiben still. Konfid' +
    'enz hoch. Schnellkorrektur: RootKey := HKEY_CURRENT_USER."',
    '    },',
    '    {',
    '      "id": "now-for-elapsed-time",',
    '      "name": "Laufzeit mit Now gemessen",',
    '      "description": "Eine Variable, der Now zugewiesen wird und die in derselben Routine danach in Now - Start, Ende - Start oder MilliSecondsBetween, SecondsBetween, MinutesBetween, HoursBetween, Da' +
    'ysBetween bzw. den …Span-Funktionen vorkommt: Die Laufzeit wird mit der Uhrzeit gemessen, grob aufgelöst und falsch bei Zeitumstellung oder Uhrabgleich. TStopwatch ist genau und monoton. Zuweisungen i' +
    'n einer anderen Routine (Felder) und im anderen Zweig von {$IFDEF} bleiben still. Konfidenz hoch. Schnellkorrektur, wenn die Variable eine lokale TDateTime ist (auch var Start := Now) und nur für Mill' +
    'iSecondsBetween, SecondsBetween oder MinutesBetween mit Now dient: TStopwatch.StartNew und ElapsedMilliseconds (div 1000 bzw. div 60000), die Variable heißt danach Uhr, wenn der Name frei ist, System.' +
    'Diagnostics kommt ins uses."',
    '    },',
    '    {',
    '      "id": "money-as-float",',
    '      "name": "Geldbetrag als Gleitkommazahl",',
    '      "description": "Feld, Variable, Parameter oder Property, deren Name einen Geldbetrag bezeichnet (Option namePatterns), mit dem Typ Double, Single, Extended oder Real: Binäres Gleitkomma rundet C' +
    'ent-Beträge falsch (0.1 + 0.2), Currency rechnet sie exakt. Maßgeblich ist der letzte Namensteil (GesamtPreis, Nettobetrag, FNetto, Preise; nicht NettoGewicht); Sätze, Faktoren, Quoten, Anteile (Steue' +
    'rsatz, PriceFactor) und Prüfsummen bleiben still. Mehrdeutige Wörter (Amount, Summe, Sum, Total: Menge bzw. Summe von irgendetwas) zählen nur mit Geldbezug in Typ bzw. Routine: ein anderer Geldname, C' +
    'urrency oder Wörter wie Cent, Euro, Rabatt, Rechnung, Zahlung, Kosten (Lighten(AColor, AAmount: Double) bleibt still). Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingescha' +
    'ltet und minConfidence low ist. Schnellkorrektur, wenn alle Namen der Deklaration Geldbeträge sind: Typ Currency, bei Parametern auch im Kopf der Implementierung, bei Feldern und Properties auch die P' +
    'roperty bzw. das Feld hinter read und write; keine Korrektur, wenn ein Getter oder Setter mitwandern müsste. Mit checkRound meldet die Regel zusätzlich Round mit einem Geldbetrag im Argument (Banker''s' +
    ' Rounding: 2,5 wird 2).",',
    '      "options": [',
    '        {',
    '          "name": "namePatterns",',
    '          "description": "Namensteile, die einen Geldbetrag bezeichnen; Mehrzahl eingeschlossen."',
    '        },',
    '        {',
    '          "name": "checkRound",',
    '          "description": "Zusätzlich Round auf Geldbeträgen melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "string-if-chain",',
    '      "name": "Lange if-Kette über denselben String",',
    '      "description": "Eine if … else if-Kette vergleicht denselben String (Bezeichner oder A.B, keine Funktionsaufrufe) mit mindestens min Literalen: S = ''x'', ''x'' = S, SameText(S, ''x''), auch mit or ve' +
    'rknüpft, in mindestens zwei Zweigen (ein einzelnes if mit or bleibt still). case IndexStr(S, [...]) of oder ein Dictionary ist kürzer und schneller. Es zählen nur Vergleiche, die immer zusammen mit de' +
    'm Kopf übersetzt werden ({$IFDEF}-Zweige innerhalb der Kette nicht). Standard aus, Konfidenz hoch. Schnellkorrektur wie die Code-Aktion if-Kette in case umwandeln (#646): case IndexStr(…) of, IndexTex' +
    't(…) bei SameText, mit or verknüpfte Vergleiche teilen sich eine Marke, der Rest der Kette wird zum else, System.StrUtils kommt ins uses. Keine Korrektur bei Kommentaren oder Direktiven zwischen den Z' +
    'weigen, doppelten Literalen oder gemischtem = und SameText.",',
    '      "options": [',
    '        {',
    '          "name": "min",',
    '          "description": "Ab so vielen Vergleichen desselben Strings meldet die Regel; mindestens 2."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "prefer-case",',
    '      "name": "if-Kette lässt sich als case schreiben",',
    '      "description": "Eine if … else if-Kette mit mindestens min Zweigen (das abschließende else zählt mit) vergleicht denselben ordinalen Ausdruck (Ganzzahl, Zeichen, Aufzählung; ohne Seiteneffekte, ' +
    'kein Funktionsaufruf) mit Konstanten: X = a, a = X, X in [a, b..c], (X >= a) and (X <= b), auch mit or verknüpft. Die Marken sind Literale, Konstantenausdrücke, untypisierte Konstanten oder Aufzählung' +
    'swerte, ohne Doppelte und Überlappungen. Den Typ liefert die Namensauflösung; Ketten mit unbekanntem Typ und Ketten mit Direktiven bleiben still. Standard aus, Konfidenz hoch. Schnellkorrektur: die Co' +
    'de-Aktion „In case umwandeln“ (#646, refactoring.ifCase); begin … end nur, wo ein Zweig mehrere Anweisungen hat, Kommentare in den Zweigen bleiben.",',
    '      "options": [',
    '        {',
    '          "name": "min",',
    '          "description": "Ab so vielen Zweigen (das abschließende else eingeschlossen) meldet die Regel; mindestens 2."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "constant-condition",',
    '      "name": "Bedingung ist immer gleich",',
    '      "description": "Die Bedingung von if, while oder until steht fest: True, False, Vergleiche von Zahlen und untypisierte Konstanten der Datei, auch über and, or, xor und not (X or True ist immer w' +
    'ahr, X and False immer falsch). Der Zweig ist toter Code oder läuft immer. while True do und repeat … until False gelten als gewollte Endlosschleifen (deren Ausgang prüft infinite-loop). Konstanten au' +
    's switchConstants, Konstanten in einem Zweig von {$IF…} und Konstanten aus anderen Units gelten als unbekannt. Korrektur bei if: toten Zweig bzw. die Bedingung entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "switchConstants",',
    '          "description": "Konstanten, die bewusst als Schalter dienen; Bedingungen darauf werden nicht gemeldet."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "infinite-loop",',
    '      "name": "Schleife ohne Ausgang",',
    '      "description": "while True do, repeat … until False oder eine andere Schleife, deren Bedingung sie nie beendet, ohne Ausgang im Rumpf: kein Break (ein Break in einer inneren Schleife verlässt nu' +
    'r diese), Exit, raise, goto, Halt, Abort oder RunError, kein Aufruf einer Routine der Datei, die eine Ausnahme auslöst oder das Programm beendet, und keine Prüfung von Terminated (Thread-Schleifen prü' +
    'ft thread-loop-without-terminated). Anonyme Methoden im Rumpf zählen nicht. Die Aktion springt zum Schleifenkopf."',
    '    },',
    '    {',
    '      "id": "loop-condition-unchanged",',
    '      "name": "Schleifenbedingung ändert sich im Rumpf nie",',
    '      "description": "Keine Variable der while- bzw. until-Bedingung ändert sich im Rumpf: keine Zuweisung, kein Inc/Dec, kein Argument (möglicherweise var), kein Methoden- oder Mitgliedszugriff auf d' +
    'as Objekt der Bedingung, keine for-Schleife darüber. Typisch ist das vergessene Inc(I) oder Next. Gemeldet wird nur, wenn jede Variable der Bedingung eine lokale Variable oder ein Wertparameter der Ro' +
    'utine ist und mindestens eine direkt (nicht nur als X.Eigenschaft) vorkommt. Still bleiben Bedingungen mit Funktionsaufrufen, Feldern, globalen Variablen, var- und out-Parametern und Terminated, außer' +
    'dem Schleifen mit Ausgang (Break, Exit, raise …), Warteschleifen (Sleep, ProcessMessages …), with, Aufrufen lokaler Routinen und Variablen, die eine anonyme Methode erfasst. Änderungen über X[…] zähle' +
    'n nur, wenn die Bedingung X[…] liest."',
    '    },',
    '    {',
    '      "id": "loop-runs-at-most-once",',
    '      "name": "Schleife läuft höchstens einmal",',
    '      "description": "Jeder Weg durch den Rumpf einer for-, for-in-, while- oder repeat-Schleife endet mit Exit, Break, raise, Halt, Abort, RunError, ExitProcess oder dem Aufruf einer Routine der Date' +
    'i, die eine Ausnahme auslöst; die Schleife läuft also höchstens einmal. Meist fehlt ein if vor dem Sprung, oder ein Continue war gemeint. Ein Weg zählt als Sprung bei if mit else und beiden Zweigen, c' +
    'ase mit else und allen Zweigen, try … finally mit try- oder finally-Teil und try … except mit try-Teil und jedem Behandler. Still bei Continue dieser Schleife, goto bzw. Marken und bedingten Direktive' +
    'n im Rumpf; ein Break innerer Schleifen zählt nicht. Ergänzt infinite-loop und loop-condition-unchanged. Keine Korrektur, die Absicht ist unklar; steht der Sprung direkt hinter einem if ohne else, fra' +
    'gt die Meldung, ob er in den if-Zweig gehört. Sicherheit hoch.",',
    '      "options": [',
    '        {',
    '          "name": "allowFirstElement",',
    '          "description": "for-in aus einfachen Anweisungen, das mit Exit bzw. Break endet (erstes Element holen), nicht melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unconditional-recursion",',
    '      "name": "Rekursion ohne Abbruch",',
    '      "description": "Eine Routine ruft sich auf jedem Pfad selbst auf, bevor sie zurückkehren kann: Es gibt keinen Pfad ohne Selbstaufruf und kein Exit oder raise davor. Ergebnis ist ein Stapelüberla' +
    'uf. Pfade ohne Aufruf sind: if ohne else bzw. case ohne else, der Rumpf von while und for, die rechte Seite von and/or, Zweige von if-Ausdrücken und anonyme Methoden. Getter und Setter der eigenen Pro' +
    'perty meldet setter-recursion; überladene Routinen bleiben still (der Aufruf kann eine andere Überladung treffen). Das Randsymbol aus #623 zeigt jede Rekursion."',
    '    },',
    '    {',
    '      "id": "pos-arguments-swapped",',
    '      "name": "Argumente von Pos vertauscht",',
    '      "description": "Pos(Text, '';''): Pos, PosEx, AnsiPos, StartsText, StartsStr, EndsText und EndsStr (auch mit Ansi-Präfix) erwarten zuerst den gesuchten Teil, dann den Text; ContainsText und Contai' +
    'nsStr erwarten zuerst den Text. Gemeldet, wenn an der Stelle des Textes ein kurzes Literal steht (bis maxLiteralLength Zeichen, Vorgabe 3; '''' zählt als ein Zeichen, #9 ebenso) und an der Stelle des Te' +
    'ils sicher ein String: eine Variable oder ein Feld mit in der Datei deklariertem String-Typ, .Text oder .Caption, eine String-Funktion der RTL (Trim, UpperCase, LeftStr, Format …) oder eine Verkettung' +
    ' mit einem String-Teil. Zeichen bleiben still, weil Pos(C, '';,'') bewusst prüft, ob C einer der Trenner ist; ebenso unbekannte Typen, zwei Literale und Methoden anderer Objekte (Liste.Pos). Konfidenz m' +
    'ittel. Schnellkorrektur: Argumente in einer Änderung tauschen; Kommentare dazwischen bleiben.",',
    '      "options": [',
    '        {',
    '          "name": "maxLiteralLength",',
    '          "description": "Längstes Literal an der Stelle des Textes, das noch als vertauscht gilt."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "integer-division-to-float",',
    '      "name": "Ganzzahldivision an Gleitkommazahl",',
    '      "description": "Schnitt := Summe div Anzahl mit Schnitt: Double: div schneidet die Nachkommastellen ab, bevor zugewiesen wird. Ebenso Prozent := Teil div Gesamt * 100, Result einer Funktion mit ' +
    'Gleitkommaergebnis und var X: Double := A div B. Gesucht wird durch Klammern, Vorzeichen und + - * / hindurch, nicht in Aufrufen (Round(A div B)), Indizes, mod oder Vergleichen. Das Ziel muss eine Var' +
    'iable, ein Feld (auch Self.X) oder Result sein, deren Typ Single, Double, Extended, Real, Currency … in der Datei deklariert ist. TDateTime, TDate und TTime bleiben still (ganze Tage sind dort meist g' +
    'ewollt), ebenso Zuweisungen in with und Trunc(A) div Trunc(B) (auch Round, Floor, Ceil: ausdrücklich gewandelt, also gewollt ganzzahlig). Konfidenz hoch. Schnellkorrektur: div durch / ersetzen (gleich' +
    'er Vorrang)."',
    '    },',
    '    {',
    '      "id": "empty-finally",',
    '      "name": "Leerer finally-Block",',
    '      "description": "Ein finally-Block ohne Anweisung: Meist ist die Freigabe beim Umbau verloren gegangen. Steht direkt vor try X := T….Create, nennt die Meldung X.Free. Ein Block mit erklärendem Ko' +
    'mmentar gilt als bewusst und wird nicht gemeldet (wie bei empty-except); ein Block mit Compiler-Direktive ebenso nicht, weil ein anderer Zweig Code enthalten kann. Konfidenz hoch. Schnellkorrektur: tr' +
    'y, finally und end entfernen und den Rumpf ausrücken (wenn try, finally und end je allein auf ihrer Zeile stehen); als einzige Anweisung eines if-, while-, for-, with- oder case-Zweigs mit mehreren An' +
    'weisungen im Rumpf wird aus try begin."',
    '    },',
    '    {',
    '      "id": "form-resource-missing",',
    '      "name": "Formular-Unit ohne {$R *.dfm}",',
    '      "description": "Neben der Unit liegt eine .dfm bzw. .fmx, die Unit deklariert die Klasse ihres Wurzelobjekts, aber keine {$R …}-Direktive bindet eine Formulardatei ein: Beim Erzeugen des Formula' +
    'rs folgt EResNotFound. Umgekehrt meldet die Regel ein {$R *.dfm} bzw. {$R Name.dfm}, dessen Datei neben der Unit fehlt (der Compiler bricht mit F1026 ab). Eine Direktive in einem beliebigen Zweig der ' +
    'bedingten Übersetzung zählt als eingebunden. Still bleibt die Regel, wenn die Klasse der Formulardatei nicht in der Unit steht und wenn sie keine Dateien neben der Unit sieht. Korrektur: {$R *.dfm} (b' +
    'zw. {$R *.fmx}) nach implementation einfügen."',
    '    },',
    '    {',
    '      "id": "form-autocreate-and-manual",',
    '      "name": "Formular automatisch und zusätzlich von Hand erzeugt",',
    '      "description": "Die .dpr erzeugt ein Formular mit Application.CreateForm, der Code weist derselben globalen Variablen zusätzlich TfrmX.Create(…) zu. Es gibt dann zwei Instanzen, die erste bleibt' +
    ' unsichtbar im Speicher. Die automatisch erzeugten Formulare kommen aus der .dpr des Projekts, zu dem die Unit gehört; kann die Regel die .dpr lesen, muss die Klasse zum CreateForm-Aufruf passen. Stil' +
    'l bleibt sie, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil) oder vorher freigibt (Free, FreeAndNil, Release), bei lokalen Namen und gleichnamigen Feldern der eigenen Klasse und bei' +
    ' Units ohne Projekt. Sicherheit hoch. Korrektur: die Zeile mit Application.CreateForm aus der .dpr entfernen (das Formular erzeugt dann nur noch der Code)."',
    '    },',
    '    {',
    '      "id": "inherited-form-handler-without-inherited",',
    '      "name": "Ereignis-Handler im geerbten Formular ohne inherited",',
    '      "description": "Bei Formularvererbung belegt ein Vorfahr-Formular dasselbe Ereignis derselben Komponente mit einem gleichnamigen Handler, der Handler im Nachfahren ruft inherited aber nicht (meh' +
    'r) auf. Die IDE erzeugt inherited; beim Anlegen; wird es gelöscht, fällt die Logik des Vorfahren still weg. Die Formulardatei des Vorfahren kommt aus dem Index (Datei der Klasse) bzw. aus den Units de' +
    'r uses-Liste neben der Unit; die Kette folgt geerbten Formularen bis zum ersten Formular mit object. Handler mit anderem Namen gelten als bewusster Ersatz. Still ohne Formulardatei des Vorfahren. Sich' +
    'erheit hoch. Korrektur: inherited; am Anfang einfügen."',
    '    },',
    '    {',
    '      "id": "self-free-in-event-handler",',
    '      "name": "Formular gibt sich im eigenen Ereignis frei",',
    '      "description": "Free, Destroy, DisposeOf oder FreeAndNil auf Self bzw. auf die globale Variable der eigenen Formularklasse als Anweisung in einem Ereignis-Handler des Formulars oder eines seiner' +
    ' Controls. Nach der Rückkehr greift die VCL noch auf das Objekt zu: Zugriffsverletzung. Richtig ist Release oder Action := caFree in OnClose. Ereignis-Handler sind die Methoden aus der Formulardatei u' +
    'nd Methoden mit einem Parameter Sender: TObject; ein Formular ist die Wurzelklasse der Formulardatei mit ClientWidth bzw. ClientHeight oder eine direkt von TForm bzw. TCustomForm abgeleitete Klasse (R' +
    'ahmen und Datenmodule haben kein Release). Anweisungen in anonymen Methoden und with-Blöcken zählen nicht. Still ohne Formulardatei. Sicherheit hoch. Korrektur: Free durch Release ersetzen, in OnClose' +
    ' (var Action: TCloseAction) durch Action := caFree."',
    '    },',
    '    {',
    '      "id": "parallel-for-shared-write",',
    '      "name": "Gemeinsame Variable in TParallel.For geschrieben",',
    '      "description": "Der Rumpf von TParallel.For bzw. eines TTask.Run/Create/Future, der in einer Schleife entsteht, schreibt eine Variable von außerhalb ohne Sperre: Summe := Summe + …, Inc/Dec oder' +
    ' eine andere Zuweisung, oder er verändert eine Sammlung von außerhalb (Add, Delete, Clear, Insert, Remove …). Die Durchläufe laufen gleichzeitig; Additionen gehen verloren oder die Liste wird beschädi' +
    'gt. Von außerhalb heißt: lokale Variable oder Parameter der umgebenden Routine, Feld ihrer Klasse oder globale Variable der Unit; Namen unbekannter Herkunft bleiben still. Rümpfe mit Sperre (TMonitor,' +
    ' Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked), Zugriffe über Index (Werte[I] := …) und verschachtelte anonyme Methoden (Synchronize, Queue) zählen nicht. Typen aus threadSafeTypes gelten ' +
    'als threadsicher. Sicherheit mittel. Korrekturen: TInterlocked.Add/Increment/Decrement bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs), System.TMonitor.Enter/Exit in try … finally um den Sam' +
    'mlungsaufruf.",',
    '      "options": [',
    '        {',
    '          "name": "threadSafeTypes",',
    '          "description": "Typen, die als threadsicher gelten; ihre Sammlungsaufrufe bleiben still."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "thread-unsafe-increment",',
    '      "name": "Zähler im Thread ohne TInterlocked",',
    '      "description": "Inc, Dec, X := X + 1 oder X := X - 1 ohne Sperre auf einer globalen Variablen in Execute eines TThread-Nachfahren bzw. auf einem Feld oder einer globalen Variablen im Rumpf von T' +
    'Task.Run/Create/Future außerhalb von Schleifen und von TThread.CreateAnonymousThread. Inc ist nicht atomar: zählen mehrere Threads gleichzeitig, gehen Erhöhungen verloren. Thread-Klassen kommen aus de' +
    'r Unit (auch über Zwischenklassen) und aus dem Index. Eigene Felder des Threads in Execute und eingefangene lokale Variablen eines einzelnen Tasks haben nur einen Schreiber und bleiben still, ebenso R' +
    'ümpfe mit Sperre (TMonitor, Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked) und verschachtelte anonyme Methoden (Synchronize, Queue). Tasks in Schleifen und TParallel.For meldet parallel-for' +
    '-shared-write. Sicherheit mittel. Korrektur: TInterlocked.Increment/Decrement/Add bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs)."',
    '    },',
    '    {',
    '      "id": "constant-expression-error",',
    '      "name": "Fehler in einem konstanten Ausdruck",',
    '      "description": "Ein konstanter Ausdruck teilt durch null (wie E2098) oder läuft über (wie E2099: über Int64 hinaus, wenn alle Operanden ein Vorzeichen haben, etwa High(Int64) + 1, sonst über UIn' +
    't64 hinaus), ein Bereich hat die Untergrenze über der Obergrenze (array[5..1], wie E2011), eine Konstante verletzt einen ganzzahligen Typ fester Größe oder einen Teilbereichstyp (wie E1012; Werte, die' +
    ' nur als gleich breite Zahl mit anderem Vorzeichen passen, etwa $FFFFFFFF für Integer oder -1 für Cardinal, wie W1012 als Warnung; bei Zuweisungen nur Werte außerhalb von 0..127), ein konstanter Index' +
    ' liegt außerhalb eines statischen Arrays der Datei oder eine einzelne case-Marke außerhalb des Ganzzahltyps des case-Ausdrucks (wie E1012), ein Hex-, Binär- oder Oktalliteral braucht mehr als 64 Bit (' +
    'wie E2102; an Int64 zugewiesen zusätzlich wie W1012), eine Menge hat mehr als 256 Elemente (set of 0..300, set of Word, wie E2028) oder eine Sichtbarkeitsmenge in {$RTTI} enthält Zahlen oder Strings s' +
    'tatt vcPrivate, vcProtected, vcPublic und vcPublished (wie E2572). Atlas wertet Literale, Konstanten (auch aus anderen Units) und SizeOf/High/Low von Typen fester Größe aus; eine Konstante aus einem {' +
    '$IF}-Zweig zählt nur, wo die geprüfte Stelle mit ihr zusammen übersetzt wird. Ausdrücke mit unbekannten Teilen bleiben still."',
    '    },',
    '    {',
    '      "id": "default-parameter-invalid",',
    '      "name": "Unzulässiger Standardwert eines Parameters",',
    '      "description": "Standardwerte, die der Compiler ablehnt: mehrere Namen mit einem gemeinsamen Standardwert (A, B: Integer = 0, wie E2237), ein Parameter ohne Standardwert nach einem mit Standardw' +
    'ert (wie E2238), var- und out-Parameter mit Standardwert (wie E2239) Records oder statische Arrays mit Standardwert (wie E2268) sowie Mengen über 4 Byte mit Standardwert (wie E2146, erlaubt sind nur k' +
    'leine Mengen; mittlere Konfidenz). Gilt für Routinen, Methoden und Prozedurtypen. Korrekturen: Parameter einzeln deklarieren; Parameter mit Standardwert ans Ende verschieben, auch im zugehörigen Kopf ' +
    'der Deklaration bzw. Implementierung derselben Datei (Aufrufe ändert sie nicht)."',
    '    },',
    '    {',
    '      "id": "signed-unsigned-mix",',
    '      "name": "Vorzeichenbehaftet und vorzeichenlos gemischt",',
    '      "description": "Vergleich oder Rechnung (+, -, *, div, mod) mit einem vorzeichenbehafteten und einem vorzeichenlosen Operanden, deren Typen sicher bekannt sind (Variablen, Felder, Properties, Fu' +
    'nktionsergebnisse, eigene Aliase). Mit UInt64 wird der ganze Ausdruck vorzeichenlos gerechnet, ein negativer Wert wird zu einer riesigen Zahl (wie W1073, beim Vergleich wie W1023); mit Cardinal/DWORD ' +
    'und einem vorzeichenbehafteten Typ bis 32 Bit werden beide Operanden auf Int64 erweitert (wie W1023/W1024). Still bei Byte und Word, Cardinal mit Int64, Literalen, Konstanten, NativeInt/NativeUInt und' +
    ' unbekannten Typen. Mittlere Konfidenz. Korrektur: den vorzeichenlosen Operanden in Int64 umwandeln."',
    '    },',
    '    {',
    '      "id": "narrowing-assignment",',
    '      "name": "Zuweisung mit möglichem Datenverlust",',
    '      "description": "Eine Zuweisung oder Inline-Variable mit einem Wert, dessen Typ breiter ist als das Ziel, ohne ausdrückliche Umwandlung: Int64 an Integer, NativeInt an Integer (Win64) und über di' +
    'e Option types z. B. Double an Single oder Extended an Double. Wie W1072 (Gleitkomma) und W1066 (Extended an Double); Ganzzahlen ohne Code, weil Delphi 13 W1071 auch mit {$WARN IMPLICIT_INTEGER_CAST_L' +
    'OSS ON} nicht meldet. Gemeldet wird nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse, eigene Aliase und ganzzahlige Rechnungen daraus); Literale und ausdrü' +
    'ckliche Umwandlungen bleiben still. Standardmäßig aus; mittlere Konfidenz. Korrekturen: ausdrücklich umwandeln; den Typ der Deklaration des Ziels vergrößern (einzelne Variable aus derselben Datei).",',
    '      "options": [',
    '        {',
    '          "name": "types",',
    '          "description": "Gemeldete Paare Quelltyp>Zieltyp, z. B. Double>Single oder Extended>Double."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "typed-constant-modified",',
    '      "name": "Typisierte Konstante verändert",',
    '      "description": "Einer typisierten Konstante (const Zaehler: Integer = 0) wird etwas zugewiesen (wie W1017, auch einem Element oder Record-Feld davon), oder sie wird als var- oder out-Argument üb' +
    'ergeben, auch an Inc, Dec, Include, Exclude, Delete, SetLength und ähnliche (wie W1016). Gemeint war meist eine Variable; übersetzbar ist das nur mit {$J+}, und gilt {$J+} vor der Deklaration, schweig' +
    't die Regel wie dcc. Gilt vor der Deklaration in derselben Datei oder in einer davor eingebundenen Include-Datei {$J-} bzw. {$WRITEABLECONST OFF}, meldet Atlas einen Fehler (wie E2064 bzw. E2197). Daz' +
    'u 0 als Wert einer Zeigerkonstante oder einer initialisierten Zeigervariable (wie W1013). Korrekturen: eine Konstante auf Unit-Ebene in eine Variable mit Initialwert umwandeln (der const-Abschnitt wir' +
    'd bei Bedarf geteilt; lokale typisierte Konstanten behalten ihren Wert zwischen Aufrufen und bekommen keine Korrektur); nil statt 0 schreiben."',
    '    },',
    '    {',
    '      "id": "string-length-limit",',
    '      "name": "String-Grenze überschritten",',
    '      "description": "Ein String-Literal wird an ein Ziel vom Typ string[N] oder ShortString gekürzt: Zuweisung, typisierte Konstante oder initialisierte Variable, auch über eigene Aliase, string[Kons' +
    'tante] und Felder aus anderen Units (wie W1014). Vor Delphi 12 (delphiVersion unter 23) darf ein Literal in Anführungszeichen höchstens 255 Zeichen haben (wie E2056), und ein resourcestring höchstens ' +
    '4096 Zeichen, mit + verbundene Literale eingerechnet (wie E2381); beides sind Fehler. Gezählt wird wie geschrieben, '''' und #13 zählen als ein Zeichen. Korrekturen: das Ziel als string deklarieren (ein' +
    'zelne Variable oder typisierte Konstante derselben Datei; Record-Felder behalten ihre Größe); das Literal in Stücke zu 255 Zeichen teilen, verbunden mit +."',
    '    },',
    '    {',
    '      "id": "dynamic-array-misuse",',
    '      "name": "New, Dispose oder SetLength falsch für dynamische Arrays",',
    '      "description": "New (wie E2255) oder Dispose (wie E2008 in Delphi 13, dokumentiert als E2256) auf einem dynamischen Array, SetLength ohne Länge (wie E2246), New mit Länge auf einem Typ, der kein' +
    ' dynamisches Array ist (wie E2008 in Delphi 13, dokumentiert als E2307), und New(TArrayTyp) ohne Länge (wie E2308). Häufig in altem Code, der von Zeigern auf dynamische Arrays umgestellt wurde. Die Re' +
    'gel meldet nur, wenn die Namensauflösung Variable bzw. Typ sicher kennt; Aliase werden verfolgt (TWerte = array of Double), TBytes und die übrigen dynamischen Arrays der RTL gelten auch ohne Index; of' +
    'fene Array-Parameter und Zeiger bleiben still. Korrekturen: Dispose(A) wird A := nil, New(A) wird SetLength(A, 1)."',
    '    },',
    '    {',
    '      "id": "local-routine-as-callback",',
    '      "name": "Lokale Routine als Prozedurvariable",',
    '      "description": "Eine lokale (verschachtelte) Routine wird einer Variablen oder einem Parameter eines prozeduralen Typs ohne of object zugewiesen (wie E2094), oder eine typisierte Konstante einer' +
    ' Routine nimmt die Adresse einer lokalen Variablen (wie E2278). Gemeint ist meist eine anonyme Methode oder eine Routine der Unit. Die Regel meldet nur, wenn die Namensauflösung den Zieltyp sicher ken' +
    'nt; Methodenzeiger und Methodenreferenzen bleiben still, weil der Compiler sie mit anderen Codes meldet, ebenso @Routine (ein untypisierter Zeiger). Korrektur: die Routine als Routine der Unit vor die' +
    ' umgebende Routine verschieben, wenn sie nichts aus ihr nutzt (keine lokalen Namen weiter außen, keine Klassenmitglieder ohne Präfix)."',
    '    },',
    '    {',
    '      "id": "hresult-integer-mix",',
    '      "name": "Integer und HRESULT vertauscht",',
    '      "description": "Eine Klasse implementiert eine Interface-Methode mit HRESULT-Ergebnis über eine Methode mit Integer- (bzw. LongInt-) Ergebnis oder umgekehrt (wie W1008; die Delphi-Hilfe nennt X1' +
    '008). Beide sind 32 Bit groß, deshalb fällt es nicht auf; die Bedeutung der Werte (S_FALSE als Erfolg) geht aber verloren; wichtig für COM- und OTA-Code. Zugeordnet wird über Name und Parametertypen s' +
    'amt Zuordnungen wie function IFoo.Bar = Baz; Interfaces samt ihren Vorfahren kommen aus der Datei bzw. dem Index. Stehen Varianten in bedingten Zweigen, meldet die Regel nur, wenn jede Variante abweic' +
    'ht. Korrektur: den Ergebnistyp in Deklaration und Implementierung an das Interface angleichen."',
    '    },',
    '    {',
    '      "id": "invalid-var-argument",',
    '      "name": "Ungültiges Argument für einen var- oder out-Parameter",',
    '      "description": "Ein var- oder out-Parameter bekommt etwas, das keine Variable ist: eine Konstante, einen konstanten Ausdruck wie cMax + 1, einen const-Parameter, eine Property oder ein Funktions' +
    'ergebnis (wie E2197), eine Konstante für ein offenes Array (wie E2192) oder einen Ausdruck (wie E2036); auch @ vor einem arithmetischen oder logischen Ausdruck meldet die Regel (wie E2036). Ein String' +
    '-Element für einen Zeichen-Parameter (S[1]) ist für dcc eine Variable und bleibt still (E2354 gibt es nur unter .NET, #1383). Gemeldet nur für Routinen ohne Überladungen, deren Kopf aus der Datei oder' +
    ' dem Index bekannt ist; eingebaute Routinen wie Inc oder Move und untypisierte var-Parameter nehmen mehr an und bleiben still. Typisierte Konstanten zählen als Konstanten, außer mit {$J+}. Korrektur: ' +
    'eine lokale Variable vom Typ des Parameters übergeben, bei Properties mit write mit Rückschreiben."',
    '    },',
    '    {',
    '      "id": "condition-not-boolean",',
    '      "name": "Bedingung ist kein Boolean",',
    '      "description": "Die Bedingung von if, while, until oder eines bedingten Ausdrucks hat sicher einen Typ, der kein Boolean ist: Zahl, Zeiger, Klasse, Interface, String oder Zeichen (wie E2012). An' +
    'ders als C verlangt Delphi einen Boolean. Gemeldet nur bei sicher bekanntem Typ; Boolean-Typen wie LongBool, Aufzählungen, Aliase und unbekannte Typen bleiben still. Korrektur: <> 0 (Alternative > 0),' +
    ' <> nil (Alternative Assigned), <> '''' bzw. <> #0 ergänzen."',
    '    },',
    '    {',
    '      "id": "type-mismatch",',
    '      "name": "Inkompatible Typen",',
    '      "description": "Zuweisung, Argument, var-Parameter, Operator, Typumwandlung oder prozeduraler Typ mit unverträglichen Typen, beide sicher bekannt: Integer := ''abc'', ein Klassenparameter mit Stan' +
    'dardwert 0, ein statisches Array := nil, eine Prozedur ohne Ergebnis als Wert, string + Integer oder [1] + [''a''] (wie E2010); ein Operator, der für einen Operanden nicht definiert ist, etwa string - C' +
    'har, Double div 2, not ''a'' oder X is Integer (wie E2015); ein var-Argument mit anderem Typ als der Parameter, etwa Byte für Integer (wie E2033); Byte(S) eines langen Strings und die Umwandlung einer G' +
    'leitkommazahl in einen Ordinaltyp (wie E2089); Inc/Dec mit einer Gleitkommazahl oder einem String als Schrittweite und Ptr(S) (wie E2008); eine Routine mit anderer Parameterliste für einen prozedurale' +
    'n Typ bzw. eine Methode für einen Typ ohne of object und umgekehrt (wie E2009); von überladenen Routinen passt keine zum prozeduralen Typ (wie E2010). Wie bei dcc hat Result den Typ aus dem interface-' +
    'Teil, und von zwei Deklarationen desselben lokalen Namens gilt die letzte. Gemeldet nur, wenn beide Seiten sicher bekannt sind und ihre Deklarationen immer mit der Stelle übersetzt werden; Records (cl' +
    'ass operator Implicit), Variant, Zeiger, Teilbereiche, Generics, überladene Routinen und with-Blöcke bleiben still. Keine Korrektur: Welche Seite falsch ist, weiß nur der Entwickler."',
    '    },',
    '    {',
    '      "id": "for-in-not-enumerable",',
    '      "name": "for-in über einen Typ ohne Enumerator",',
    '      "description": "Eine for-in-Schleife läuft über einen Typ, der sich nicht aufzählen lässt: Zahl, Zeiger, Zeichen oder Boolean, oder eine Klasse, ein Record bzw. Interface ohne öffentliches GetEn' +
    'umerator, auch nicht geerbt oder aus einem Helper (wie E2430); oder der Enumerator aus GetEnumerator hat kein öffentliches MoveNext bzw. Current (wie E2431). Strings, Arrays und Mengen gehen. Gemeldet' +
    ' nur, wenn der Typ und alle Vorfahren bekannt sind; generische und unbekannte Typen bleiben still. Keine Korrektur; hat der Typ Count, nennt die Meldung eine Schleife mit Index."',
    '    },',
    '    {',
    '      "id": "type-kind-required",',
    '      "name": "Ausdruck oder Deklaration hat nicht die geforderte Typart",',
    '      "description": "Eine Operation verlangt eine Typart, die der Operand sicher nicht hat: ein Index auf einer Zahl, einem Boolean, Zeichen oder Aufzählungswert (wie E2016); ^ auf einem solchen Wert' +
    ', einer Klasse, einem Record oder Interface (wie E2017); Punkt oder with auf einem solchen Wert (wie E2018); ein object-Typ mit einem Vorfahr, der kein object-Typ ist, TypeOf auf einem einfachen Wert ' +
    'und Dispose mit Destruktor auf einem Zeiger auf einen einfachen Typ (wie E2019); eine Klasse mit einem Record, einer Klassenreferenz, Aufzählung oder einem einfachen Typ als Vorfahr (wie E2021); ein C' +
    'lass-Helper, dessen Vorfahr kein Helper ist (wie E2022); New mit Konstruktor auf einem Zeiger auf einen einfachen Typ (wie E2467); ein Record-Helper für eine Klasse oder ein Interface (wie E2474); ein' +
    'e Methode ohne class über den Klassentyp aufgerufen, außerhalb von Methoden der Klasse und ihrer Nachfahren (wie E2076); Slice außerhalb eines Arguments für ein offenes Array (wie E2193); ein Record i' +
    'n einem Array an array of const (wie E2150); Write/Writeln bzw. Read/Readln mit einer Klasse, einem Record oder Interface (wie E2054, E2055). Gemeldet nur bei sicher bekanntem Typ: unbekannte Typen, b' +
    'edingte Deklarationen, sichtbare Helper, Units außerhalb des Index, Records mit Implicit-Operator und unbekannte Vorfahren bleiben still. Korrekturen: ^ vor einem Punkt bei Klassen, Records und Interf' +
    'aces entfernen; in Write/Writeln Objekt.ToString schreiben."',
    '    },',
    '    {',
    '      "id": "inherited-abstract-call",',
    '      "name": "inherited ruft eine abstrakte Methode auf",',
    '      "description": "inherited mit ausdrücklichem Methodennamen, etwa inherited Zeichnen(C), obwohl die Methode im Vorfahren abstract ist: Der Aufruf löst zur Laufzeit EAbstractError aus. Der Compile' +
    'r übersetzt ihn ohne Fehler. Ein bloßes inherited; übergeht der Compiler bei abstrakten Methoden still; das meldet die Regel nicht. Die Methode löst die Namensauflösung samt Überladungen auf; gemeldet' +
    ' wird nur, wenn jede passende Überladung abstrakt ist. Korrektur: den Aufruf entfernen, wenn er als eigene Anweisung in einem begin…end steht."',
    '    },',
    '    {',
    '      "id": "override-only-inherited",',
    '      "name": "override ruft nur inherited auf",',
    '      "description": "Eine überschreibende Methode, deren Rumpf nur die geerbte Methode aufruft: ein bloßes inherited;, inherited Name oder inherited Name(A, B) mit den eigenen Parametern in unverände' +
    'rter Reihenfolge, in Funktionen nur Result := inherited Name(…). Sie tut nichts Eigenes und täuscht ein geändertes Verhalten vor. Still, wenn die Methode die Sichtbarkeit der geerbten ändert (protecte' +
    'd zu public), ein Attribut, Standardwerte oder die Direktiven final, deprecated, experimental, platform, library oder reintroduce trägt, lokale Deklarationen, mehr als eine Anweisung, Kommentare oder ' +
    'bedingte Direktiven im Rumpf hat oder die überschriebene Methode unbekannt ist (Vorfahr nicht im Index; virtuelle Methoden von TObject gelten als public). Sicherheit hoch. Korrektur: Deklaration und R' +
    'umpf entfernen, samt XMLDoc-Kommentaren und der Leerzeile hinter dem Rumpf."',
    '    },',
    '    {',
    '      "id": "inherited-without-ancestor",',
    '      "name": "inherited ohne Methode im Vorfahr",',
    '      "description": "Ein bloßes inherited; in einer Methode, die kein Vorfahr deklariert (neue Methode, kein override), tut nichts. Das deutet auf ein vergessenes override oder einen Tippfehler im Na' +
    'men. Nicht gemeldet: Message-Handler (inherited ruft dort DefaultHandler), Klassen- und statische Methoden, Konstruktoren und Destruktoren, override und reintroduce, inherited in anonymen Methoden, Vo' +
    'rfahren mit einem gleichnamigen Mitglied (auch nicht virtuell) und unbekannte Vorfahren. Vorfahren aus anderen Units liefert der Symbolindex; Methoden von TObject gelten als bekannt, wenn System nicht' +
    ' im Index steht. Sicherheit hoch. Korrektur: inherited entfernen, wenn es als eigene Anweisung in einem begin…end steht."',
    '    },',
    '    {',
    '      "id": "redundant-jump",',
    '      "name": "Überflüssiges Exit oder Continue",',
    '      "description": "Ein bloßes Exit; als letzte Anweisung einer Routine oder anonymen Methode, oder ein bloßes Continue; als letzte Anweisung eines Schleifenrumpfs (for, for-in, while, repeat), auch' +
    ' im letzten Zweig eines if am Ende (der then-Zweig nur ohne else; then Continue else … bewacht eine else-if-Kette). Der Sprung ändert nichts. Nicht gemeldet: Exit mit Wert, Sprünge in try…finally oder' +
    ' try…except (der Sprung löst den finally-Teil bewusst aus), in case, qualifizierte Namen wie System.Continue, Anweisungen mit goto-Marke und Rümpfe mit bedingten Direktiven. Sicherheit hoch. Korrektur' +
    ': die Anweisung entfernen, wenn sie in einem begin…end oder direkt in repeat steht."',
    '    },',
    '    {',
    '      "id": "generic-constraint-violated",',
    '      "name": "Typargument verletzt eine Einschränkung",',
    '      "description": "Ein Typargument erfüllt die Einschränkung seines Typparameters nicht: class (wie E2511), record (wie E2512), constructor (wie E2513), ein Interface (wie E2514) oder eine Basiskla' +
    'sse (wie E2515). In Methoden eines generischen Typs dieser Datei meldet die Regel außerdem T.Create ohne constructor-Einschränkung (wie E2568) und Methodenaufrufe auf Werten eines Typparameters ganz o' +
    'hne Einschränkung (wie E2571). Den generischen Typ löst die Namensauflösung samt Zahl der Typparameter auf, seine Einschränkungen stammen aus seiner Deklaration in der Datei oder im Symbolindex. Argum' +
    'ente, die selbst Typparameter sind, Aliase und Typen mit unvollständiger Vorfahrenkette meldet die Regel nicht. Korrektur für einen Typparameter dieser Datei, der allein in seiner Gruppe steht: die Ei' +
    'nschränkung ergänzen (T: class, constructor bzw. T: class)."',
    '    },',
    '    {',
    '      "id": "generic-inference-failed",',
    '      "name": "Typargumente lassen sich nicht ableiten",');

implementation

end.
