unit Atlas.Common.Compiler.Edition;

// Ausgabe der Delphi-Installation vorher erkennen (#261), statt aus einem
// fehlgeschlagenen Lauf zu raten: Gibt es bin\dcc32.exe bzw. bin\dcc64.exe,
// und meldet der Compiler bei einem Probelauf ohne Argumente den Lizenztext
// der Starter bzw. Community Edition („This version of the product does not
// support command line compiling.“)? Erscheint der Lizenztext später in der
// Ausgabe eines echten Laufs, gilt dasselbe.
// Das Ergebnis gilt je BDS-Wurzel und Version (TCompilerEditionCache, als
// JSON in %LOCALAPPDATA%\Atlas\compiler-editions.json, Lesen und Schreiben
// übernimmt der Host). Ändert sich die geprüfte Compiler-Datei (Größe,
// Zeitstempel; „Stamp“), gilt der Eintrag nicht mehr und Atlas prüft erneut,
// etwa nach dem Wechsel auf eine Professional-Lizenz.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  /// <summary>Unknown = noch nicht geprüft oder unklar (wie nutzbar behandelt); CommandLine = dcc nutzbar;
  /// NoCommandLine = Lizenztext der Starter bzw. Community Edition; Missing = kein dcc32/dcc64 in bin.</summary>
  TCompilerEdition = (Unknown, CommandLine, NoCommandLine, Missing);
  {$SCOPEDENUMS OFF}

  TCompilerEditionEntry = record
    /// <summary>BDS-Wurzel wie $(BDS), z. B. C:\Program Files (x86)\Embarcadero\Studio\37.0.</summary>
    Root: string;
    /// <summary>BDS-Version, z. B. "37.0".</summary>
    Version: string;
    Edition: TCompilerEdition;
    /// <summary>Fingerabdruck der geprüften Compiler-Datei (Größe und Zeitstempel); '' ohne Datei.</summary>
    Stamp: string;
    /// <summary>Zeitpunkt der Prüfung als ISO-8601-Text (UTC); nur zur Anzeige.</summary>
    Checked: string;
  end;

  TCompilerEditions = class
  public
    /// <summary>True, wenn ALine der Lizenztext einer Ausgabe ohne Kommandozeilen-Compiler ist (englisch oder
    /// deutsch, Groß- und Kleinschreibung egal).</summary>
    class function IsLicenseLine(const ALine: string): Boolean; static;
    /// <summary>True, wenn eine Zeile von AOutput der Lizenztext ist.</summary>
    class function HasLicenseText(const AOutput: TArray<string>): Boolean; static;
    /// <summary>Ergebnis eines Probelaufs: AExists = Compiler-Datei vorhanden, AOutput = Ausgabe des Laufs
    /// ohne Argumente (leer, wenn er nicht lief).</summary>
    class function Detect(AExists: Boolean; const AOutput: TArray<string>): TCompilerEdition; static;
    /// <summary>"unknown", "commandLine", "noCommandLine", "missing".</summary>
    class function ToText(AEdition: TCompilerEdition): string; static;
    /// <summary>Umkehrung von ToText; Unbekanntes wird Unknown.</summary>
    class function FromText(const AText: string): TCompilerEdition; static;
    /// <summary>Lesbarer Grund für Meldung und Log, z. B. „kein Kommandozeilen-Compiler (Starter Edition)“.</summary>
    class function Describe(AEdition: TCompilerEdition): string; static;
  end;

  /// <summary>Zwischenspeicher der Erkennung je BDS-Wurzel und Version; nicht threadsicher.</summary>
  TCompilerEditionCache = class
  public const
    cFormatVersion = 1;
    cFileName = 'compiler-editions.json';
  private
    FEntries: TList<TCompilerEditionEntry>;
    function IndexOf(const ARoot, AVersion: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Liest den Text von ToJson; unlesbarer Text ergibt einen leeren Speicher.</summary>
    procedure Load(const AText: string);
    function ToJson: string;
    /// <summary>Gespeicherte Ausgabe für ARoot und AVersion, wenn AStamp zum Eintrag passt; sonst Unknown.</summary>
    function Find(const ARoot, AVersion, AStamp: string): TCompilerEdition;
    /// <summary>Ersetzt den Eintrag gleicher Wurzel und Version (Groß- und Kleinschreibung der Wurzel egal).</summary>
    procedure Store(const AEntry: TCompilerEditionEntry);
    function Count: Integer;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditionText = (NoCommandLineCompilerStarter, NoCommandLineCompilerStarter2, CommandLineCompilerNotChecked,
    CommandLineCompilerAvailable);

const
  cTexts: array[TEditionText] of TAtlasText = (
    (De: 'kein Kommandozeilen-Compiler (Starter Edition: dcc32/dcc64 melden nur den Lizenztext)';
     En: 'no command-line compiler (Starter Edition: dcc32/dcc64 only report the license text)'),
    (De: 'kein Kommandozeilen-Compiler (Starter Edition: dcc32/dcc64 fehlen im Ordner bin)';
     En: 'no command-line compiler (Starter Edition: dcc32/dcc64 missing in the bin folder)'),
    (De: 'Kommandozeilen-Compiler noch nicht geprüft'; En: 'Command-line compiler not checked yet'),
    (De: 'Kommandozeilen-Compiler vorhanden'; En: 'Command line compiler available'));

{$SCOPEDENUMS OFF}

const
  cEditionTexts: array[TCompilerEdition] of string = ('unknown', 'commandLine', 'noCommandLine', 'missing');

{ TCompilerEditions }

class function TCompilerEditions.IsLicenseLine(const ALine: string): Boolean;
var
  mText: string;
  mCommandLine, mRefused: Boolean;
begin
  mText := LowerCase(ALine);
  // Bekannt (Community/Starter, englisch): "This version of the product does not support command line compiling."
  // Deutsch sinngemäß: "Diese Version des Produkts unterstützt keine Kompilierung über die Befehlszeile."
  mCommandLine := (Pos('command line', mText) > 0) or (Pos('command-line', mText) > 0) or
    (Pos('commandline', mText) > 0) or (Pos('befehlszeile', mText) > 0) or (Pos('kommandozeile', mText) > 0);
  mRefused := (Pos('not support', mText) > 0) or (Pos('not supported', mText) > 0) or
    (Pos('nicht unterstützt', mText) > 0) or (Pos('unterstützt keine', mText) > 0) or
    (Pos('unterstützt nicht', mText) > 0) or ((Pos('unterstützt', mText) > 0) and (Pos('nicht', mText) > 0));
  Result := mCommandLine and mRefused;
end;

class function TCompilerEditions.HasLicenseText(const AOutput: TArray<string>): Boolean;
var
  mLine: string;
begin
  for mLine in AOutput do
  begin
    if IsLicenseLine(mLine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCompilerEditions.Detect(AExists: Boolean; const AOutput: TArray<string>): TCompilerEdition;
var
  mLine: string;
begin
  if not AExists then
  begin
    Exit(TCompilerEdition.Missing);
  end;
  if HasLicenseText(AOutput) then
  begin
    Exit(TCompilerEdition.NoCommandLine);
  end;
  // Ein nutzbarer Compiler nennt sich ohne Argumente mit Kopfzeile und Aufrufhilfe.
  for mLine in AOutput do
  begin
    if Trim(mLine) <> '' then
    begin
      Exit(TCompilerEdition.CommandLine);
    end;
  end;
  // Keine Ausgabe: unklar; der echte Lauf entscheidet.
  Result := TCompilerEdition.Unknown;
end;

class function TCompilerEditions.ToText(AEdition: TCompilerEdition): string;
begin
  Result := cEditionTexts[AEdition];
end;

class function TCompilerEditions.FromText(const AText: string): TCompilerEdition;
var
  mEdition: TCompilerEdition;
begin
  for mEdition := Low(TCompilerEdition) to High(TCompilerEdition) do
  begin
    if SameText(cEditionTexts[mEdition], AText) then
    begin
      Exit(mEdition);
    end;
  end;
  Result := TCompilerEdition.Unknown;
end;

class function TCompilerEditions.Describe(AEdition: TCompilerEdition): string;
begin
  case AEdition of
    TCompilerEdition.CommandLine:
      Result := cTexts[TEditionText.CommandLineCompilerAvailable].Text;
    TCompilerEdition.NoCommandLine:
      Result := cTexts[TEditionText.NoCommandLineCompilerStarter].Text;
    TCompilerEdition.Missing:
      Result := cTexts[TEditionText.NoCommandLineCompilerStarter2].Text;
  else
    Result := cTexts[TEditionText.CommandLineCompilerNotChecked].Text;
  end;
end;

{ TCompilerEditionCache }

constructor TCompilerEditionCache.Create;
begin
  inherited Create;
  FEntries := TList<TCompilerEditionEntry>.Create;
end;

destructor TCompilerEditionCache.Destroy;
begin
  FEntries.Free;
  inherited;
end;

function TCompilerEditionCache.Count: Integer;
begin
  Result := FEntries.Count;
end;

function TCompilerEditionCache.IndexOf(const ARoot, AVersion: string): Integer;
var
  mRoot: string;
begin
  mRoot := TProjectPaths.Normalize(ARoot);
  for Result := 0 to FEntries.Count - 1 do
  begin
    if SameText(TProjectPaths.Normalize(FEntries[Result].Root), mRoot) and (FEntries[Result].Version = AVersion) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TCompilerEditionCache.Find(const ARoot, AVersion, AStamp: string): TCompilerEdition;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(ARoot, AVersion);
  if (mIndex < 0) or (FEntries[mIndex].Stamp <> AStamp) then
  begin
    Exit(TCompilerEdition.Unknown);
  end;
  Result := FEntries[mIndex].Edition;
end;

procedure TCompilerEditionCache.Store(const AEntry: TCompilerEditionEntry);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AEntry.Root, AEntry.Version);
  if mIndex >= 0 then
  begin
    FEntries[mIndex] := AEntry;
  end
  else
  begin
    FEntries.Add(AEntry);
  end;
end;

procedure TCompilerEditionCache.Load(const AText: string);
var
  mValue, mItem: TJSONValue;
  mItems: TJSONArray;
  mEntry: TCompilerEditionEntry;
begin
  FEntries.Clear;
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if not (mValue is TJSONObject) or not TJSONObject(mValue).TryGetValue<TJSONArray>('entries', mItems) then
    begin
      Exit;
    end;
    for mItem in mItems do
    begin
      if mItem is TJSONObject then
      begin
        mEntry := Default(TCompilerEditionEntry);
        mEntry.Root := TJSONObject(mItem).GetValue<string>('root', '');
        mEntry.Version := TJSONObject(mItem).GetValue<string>('version', '');
        mEntry.Edition := TCompilerEditions.FromText(TJSONObject(mItem).GetValue<string>('edition', ''));
        mEntry.Stamp := TJSONObject(mItem).GetValue<string>('stamp', '');
        mEntry.Checked := TJSONObject(mItem).GetValue<string>('checked', '');
        if (mEntry.Root <> '') and (mEntry.Edition <> TCompilerEdition.Unknown) then
        begin
          Store(mEntry);
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

function TCompilerEditionCache.ToJson: string;
var
  mRoot, mItem: TJSONObject;
  mItems: TJSONArray;
  mEntry: TCompilerEditionEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormatVersion));
    mItems := TJSONArray.Create;
    mRoot.AddPair('entries', mItems);
    for mEntry in FEntries do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('root', mEntry.Root);
      mItem.AddPair('version', mEntry.Version);
      mItem.AddPair('edition', TCompilerEditions.ToText(mEntry.Edition));
      mItem.AddPair('stamp', mEntry.Stamp);
      mItem.AddPair('checked', mEntry.Checked);
      mItems.AddElement(mItem);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Compiler.Edition', cTexts);

end.
