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
    FormatVersion = 1;
    FileName = 'compiler-editions.json';
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
  Atlas.Common.Projects.Paths;

const
  EditionTexts: array[TCompilerEdition] of string = ('unknown', 'commandLine', 'noCommandLine', 'missing');

{ TCompilerEditions }

class function TCompilerEditions.IsLicenseLine(const ALine: string): Boolean;
var
  Text: string;
  CommandLine, Refused: Boolean;
begin
  Text := LowerCase(ALine);
  // Bekannt (Community/Starter, englisch): "This version of the product does not support command line compiling."
  // Deutsch sinngemäß: "Diese Version des Produkts unterstützt keine Kompilierung über die Befehlszeile."
  CommandLine := (Pos('command line', Text) > 0) or (Pos('command-line', Text) > 0) or
    (Pos('commandline', Text) > 0) or (Pos('befehlszeile', Text) > 0) or (Pos('kommandozeile', Text) > 0);
  Refused := (Pos('not support', Text) > 0) or (Pos('not supported', Text) > 0) or
    (Pos('nicht unterstützt', Text) > 0) or (Pos('unterstützt keine', Text) > 0) or
    (Pos('unterstützt nicht', Text) > 0) or ((Pos('unterstützt', Text) > 0) and (Pos('nicht', Text) > 0));
  Result := CommandLine and Refused;
end;

class function TCompilerEditions.HasLicenseText(const AOutput: TArray<string>): Boolean;
var
  Line: string;
begin
  for Line in AOutput do
    if IsLicenseLine(Line) then
      Exit(True);
  Result := False;
end;

class function TCompilerEditions.Detect(AExists: Boolean; const AOutput: TArray<string>): TCompilerEdition;
var
  Line: string;
begin
  if not AExists then
    Exit(TCompilerEdition.Missing);
  if HasLicenseText(AOutput) then
    Exit(TCompilerEdition.NoCommandLine);
  // Ein nutzbarer Compiler nennt sich ohne Argumente mit Kopfzeile und Aufrufhilfe.
  for Line in AOutput do
    if Trim(Line) <> '' then
      Exit(TCompilerEdition.CommandLine);
  // Keine Ausgabe: unklar; der echte Lauf entscheidet.
  Result := TCompilerEdition.Unknown;
end;

class function TCompilerEditions.ToText(AEdition: TCompilerEdition): string;
begin
  Result := EditionTexts[AEdition];
end;

class function TCompilerEditions.FromText(const AText: string): TCompilerEdition;
var
  Edition: TCompilerEdition;
begin
  for Edition := Low(TCompilerEdition) to High(TCompilerEdition) do
    if SameText(EditionTexts[Edition], AText) then
      Exit(Edition);
  Result := TCompilerEdition.Unknown;
end;

class function TCompilerEditions.Describe(AEdition: TCompilerEdition): string;
begin
  case AEdition of
    TCompilerEdition.CommandLine:
      Result := 'Kommandozeilen-Compiler vorhanden';
    TCompilerEdition.NoCommandLine:
      Result := 'kein Kommandozeilen-Compiler (Starter Edition: dcc32/dcc64 melden nur den Lizenztext)';
    TCompilerEdition.Missing:
      Result := 'kein Kommandozeilen-Compiler (Starter Edition: dcc32/dcc64 fehlen im Ordner bin)';
  else
    Result := 'Kommandozeilen-Compiler noch nicht geprüft';
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
  Root: string;
begin
  Root := TProjectPaths.Normalize(ARoot);
  for Result := 0 to FEntries.Count - 1 do
    if SameText(TProjectPaths.Normalize(FEntries[Result].Root), Root) and (FEntries[Result].Version = AVersion) then
      Exit;
  Result := -1;
end;

function TCompilerEditionCache.Find(const ARoot, AVersion, AStamp: string): TCompilerEdition;
var
  Index: Integer;
begin
  Index := IndexOf(ARoot, AVersion);
  if (Index < 0) or (FEntries[Index].Stamp <> AStamp) then
    Exit(TCompilerEdition.Unknown);
  Result := FEntries[Index].Edition;
end;

procedure TCompilerEditionCache.Store(const AEntry: TCompilerEditionEntry);
var
  Index: Integer;
begin
  Index := IndexOf(AEntry.Root, AEntry.Version);
  if Index >= 0 then
    FEntries[Index] := AEntry
  else
    FEntries.Add(AEntry);
end;

procedure TCompilerEditionCache.Load(const AText: string);
var
  Value, Item: TJSONValue;
  Items: TJSONArray;
  Entry: TCompilerEditionEntry;
begin
  FEntries.Clear;
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if not (Value is TJSONObject) or not TJSONObject(Value).TryGetValue<TJSONArray>('entries', Items) then
      Exit;
    for Item in Items do
      if Item is TJSONObject then
      begin
        Entry := Default(TCompilerEditionEntry);
        Entry.Root := TJSONObject(Item).GetValue<string>('root', '');
        Entry.Version := TJSONObject(Item).GetValue<string>('version', '');
        Entry.Edition := TCompilerEditions.FromText(TJSONObject(Item).GetValue<string>('edition', ''));
        Entry.Stamp := TJSONObject(Item).GetValue<string>('stamp', '');
        Entry.Checked := TJSONObject(Item).GetValue<string>('checked', '');
        if (Entry.Root <> '') and (Entry.Edition <> TCompilerEdition.Unknown) then
          Store(Entry);
      end;
  finally
    Value.Free;
  end;
end;

function TCompilerEditionCache.ToJson: string;
var
  Root, Item: TJSONObject;
  Items: TJSONArray;
  Entry: TCompilerEditionEntry;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(FormatVersion));
    Items := TJSONArray.Create;
    Root.AddPair('entries', Items);
    for Entry in FEntries do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('root', Entry.Root);
      Item.AddPair('version', Entry.Version);
      Item.AddPair('edition', TCompilerEditions.ToText(Entry.Edition));
      Item.AddPair('stamp', Entry.Stamp);
      Item.AddPair('checked', Entry.Checked);
      Items.AddElement(Item);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
