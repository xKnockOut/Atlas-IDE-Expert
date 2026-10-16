unit Atlas.Core.Settings.HiddenPlaces;

// Ausgeblendete Stellen in der Projektdatei .atlas (#628, #486), ohne VCL und
// Open Tools API. „Nur hier ausblenden“ und „In dieser Datei ausblenden“ an
// einem gezeichneten Element (außer Befunden mit Regel, die bekommen einen
// Unterdrückungskommentar #147) legen einen Eintrag im Abschnitt "hidden" an:
//   "hidden": [
//     {"setting": "BlockEndLabels", "file": "Source/Kunde.pas", "anchor": "TKunde.Speichern"},
//     {"setting": "InlayHints", "file": "Source/Kunde.pas"}
//   ]
// "setting" ist der Schlüssel der Einstellung des Elements, "file" der Pfad
// relativ zum Ordner der .atlas (Trenner "/"), "anchor" der Anker des Elements
// (Name der Methode, Beschriftung oder normierte Codezeile); ohne "anchor" gilt
// der Eintrag für die ganze Datei. Der Anker hängt am Inhalt, nicht an der
// Zeilennummer: Einfügen von Zeilen darüber ändert nichts.
// TAtlasHiddenIndex beantwortet beim Zeichnen schnell, ob ein Element
// ausgeblendet ist; AddTo und RemoveFrom ändern nur den Abschnitt "hidden" im
// Text der Datei (Kommentare und übrige Werte bleiben, TAtlasJsonText).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasHiddenPlace = record
    /// <summary>Schlüssel der Einstellung des Elements, z. B. "BlockEndLabels".</summary>
    Setting: string;
    /// <summary>Pfad relativ zum Ordner der .atlas, Trenner "/".</summary>
    FileName: string;
    /// <summary>Anker des Elements; '' = ganze Datei.</summary>
    Anchor: string;
    class function Create(const ASetting, AFileName, AAnchor: string): TAtlasHiddenPlace; static;
    /// <summary>Gleiche Einstellung und Datei (ohne Groß-/Kleinschreibung, "\" wie "/") und gleicher Anker.
    /// </summary>
    function SameAs(const AOther: TAtlasHiddenPlace): Boolean;
    function WholeFile: Boolean;
  end;

  TAtlasHiddenPlaces = class
  public const
    Key = 'hidden';
  public
    /// <summary>AFileName relativ zu AFolder mit "/"; False, wenn die Datei nicht unter AFolder liegt.</summary>
    class function Relative(const AFolder, AFileName: string; out ARelative: string): Boolean; static;
    /// <summary>Pfad mit "/" als Trenner, ohne "./" am Anfang.</summary>
    class function NormalizePath(const APath: string): string; static;
    class function IndexOf(const APlaces: TArray<TAtlasHiddenPlace>; const APlace: TAtlasHiddenPlace): Integer; static;
    /// <summary>JSON-Text des Abschnitts (Array, eine Zeile je Eintrag, eingerückt mit AIndent).</summary>
    class function ToJson(const APlaces: TArray<TAtlasHiddenPlace>; const AIndent, ALineBreak: string): string; static;
    /// <summary>Text der .atlas mit APlace im Abschnitt "hidden"; unverändert, wenn er schon drin steht. Leerer
    /// Text: ASkeleton als Grundlage.</summary>
    class function AddTo(const AText, ASkeleton: string; const APlace: TAtlasHiddenPlace): string; static;
    /// <summary>Text der .atlas ohne APlace; unverändert, wenn er fehlt.</summary>
    class function RemoveFrom(const AText: string; const APlace: TAtlasHiddenPlace): string; static;
    /// <summary>Einträge aus dem Text der .atlas (ohne Prüfung, für AddTo/RemoveFrom; das Lesen mit Prüfung
    /// übernimmt TAtlasTeamFile.Parse).</summary>
    class function FromText(const AText: string): TArray<TAtlasHiddenPlace>; static;
  end;

  /// <summary>Schnelle Abfrage beim Zeichnen; gilt für einen Stand der .atlas.</summary>
  TAtlasHiddenIndex = class
  private
    FFolder: string;
    /// <summary>"setting|datei" (klein) → Anker; '' im Wert steht für die ganze Datei.</summary>
    FAnchors: TObjectDictionary<string, TList<string>>;
    FLastFile: string;
    FLastRelative: string;
    FLastInside: Boolean;
    function Lookup(const ASetting, AFileName: string; out AAnchors: TList<string>): Boolean;
  public
    /// <summary>AFolder: Ordner der .atlas; leer = keine Einträge wirksam.</summary>
    constructor Create(const APlaces: TArray<TAtlasHiddenPlace>; const AFolder: string);
    destructor Destroy; override;
    function IsEmpty: Boolean;
    /// <summary>Element mit ASetting in AFileName (vollständiger Pfad) ganz ausgeblendet?</summary>
    function FileHidden(const ASetting, AFileName: string): Boolean;
    /// <summary>Element an AAnchor ausgeblendet (ganze Datei oder genau dieser Anker)?</summary>
    function Hidden(const ASetting, AFileName, AAnchor: string): Boolean;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Core.Settings.JsonText;

function IsSeparator(ACh: Char): Boolean;
begin
  Result := (ACh = '\') or (ACh = '/');
end;

{ TAtlasHiddenPlace }

class function TAtlasHiddenPlace.Create(const ASetting, AFileName, AAnchor: string): TAtlasHiddenPlace;
begin
  Result.Setting := ASetting;
  Result.FileName := TAtlasHiddenPlaces.NormalizePath(AFileName);
  Result.Anchor := AAnchor;
end;

function TAtlasHiddenPlace.SameAs(const AOther: TAtlasHiddenPlace): Boolean;
begin
  Result := SameText(Setting, AOther.Setting) and
    SameText(TAtlasHiddenPlaces.NormalizePath(FileName), TAtlasHiddenPlaces.NormalizePath(AOther.FileName)) and
    (Anchor = AOther.Anchor);
end;

function TAtlasHiddenPlace.WholeFile: Boolean;
begin
  Result := Anchor = '';
end;

{ TAtlasHiddenPlaces }

class function TAtlasHiddenPlaces.NormalizePath(const APath: string): string;
var
  Index: Integer;
begin
  Result := Trim(APath);
  for Index := 1 to Length(Result) do
    if Result[Index] = '\' then
      Result[Index] := '/';
  while Result.StartsWith('./') do
    Result := Copy(Result, 3, MaxInt);
end;

class function TAtlasHiddenPlaces.Relative(const AFolder, AFileName: string; out ARelative: string): Boolean;
var
  Folder, FileName: string;
begin
  ARelative := '';
  Folder := NormalizePath(AFolder);
  while (Folder <> '') and IsSeparator(Folder[Length(Folder)]) do
    Delete(Folder, Length(Folder), 1);
  FileName := NormalizePath(AFileName);
  Result := (Folder <> '') and (Length(FileName) > Length(Folder) + 1) and
    SameText(Copy(FileName, 1, Length(Folder)), Folder) and (FileName[Length(Folder) + 1] = '/');
  if Result then
    ARelative := Copy(FileName, Length(Folder) + 2, MaxInt);
  // Kein Ausbruch über "..": der Pfad bleibt unter dem Ordner.
  if Result and ((Pos('/../', '/' + ARelative + '/') > 0)) then
  begin
    ARelative := '';
    Result := False;
  end;
end;

class function TAtlasHiddenPlaces.IndexOf(const APlaces: TArray<TAtlasHiddenPlace>;
  const APlace: TAtlasHiddenPlace): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(APlaces) do
    if APlaces[Index].SameAs(APlace) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasHiddenPlaces.ToJson(const APlaces: TArray<TAtlasHiddenPlace>;
  const AIndent, ALineBreak: string): string;
var
  Index: Integer;
  Item: string;
begin
  if Length(APlaces) = 0 then
    Exit('[]');
  Result := '[';
  for Index := 0 to High(APlaces) do
  begin
    Item := '{"setting": ' + TAtlasJsonText.Quote(APlaces[Index].Setting) + ', "file": ' +
      TAtlasJsonText.Quote(NormalizePath(APlaces[Index].FileName));
    if APlaces[Index].Anchor <> '' then
      Item := Item + ', "anchor": ' + TAtlasJsonText.Quote(APlaces[Index].Anchor);
    Item := Item + '}';
    if Index < High(APlaces) then
      Item := Item + ',';
    Result := Result + ALineBreak + AIndent + '  ' + Item;
  end;
  Result := Result + ALineBreak + AIndent + ']';
end;

class function TAtlasHiddenPlaces.FromText(const AText: string): TArray<TAtlasHiddenPlace>;
var
  Root: TJSONObject;
  Value, Item: TJSONValue;
  Place: TAtlasHiddenPlace;
begin
  Result := nil;
  Root := TAtlasJsonText.Parse(AText);
  if Root = nil then
    Exit;
  try
    Value := Root.GetValue(Key);
    if not (Value is TJSONArray) then
      Exit;
    for Item in TJSONArray(Value) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Place := TAtlasHiddenPlace.Create(TJSONObject(Item).GetValue<string>('setting', ''),
        TJSONObject(Item).GetValue<string>('file', ''), TJSONObject(Item).GetValue<string>('anchor', ''));
      if (Place.Setting <> '') and (Place.FileName <> '') then
        Result := Result + [Place];
    end;
  finally
    Root.Free;
  end;
end;

class function TAtlasHiddenPlaces.AddTo(const AText, ASkeleton: string; const APlace: TAtlasHiddenPlace): string;
var
  Places: TArray<TAtlasHiddenPlace>;
begin
  Result := AText;
  if Trim(Result) = '' then
    Result := ASkeleton;
  Places := FromText(Result);
  if IndexOf(Places, APlace) >= 0 then
    Exit;
  Places := Places + [APlace];
  Result := TAtlasJsonText.SetValue(Result, Key, ToJson(Places, '  ', TTextLines.LineBreakOf(Result)));
end;

class function TAtlasHiddenPlaces.RemoveFrom(const AText: string; const APlace: TAtlasHiddenPlace): string;
var
  Places: TArray<TAtlasHiddenPlace>;
  Index: Integer;
begin
  Result := AText;
  Places := FromText(Result);
  Index := IndexOf(Places, APlace);
  if Index < 0 then
    Exit;
  Delete(Places, Index, 1);
  Result := TAtlasJsonText.SetValue(Result, Key, ToJson(Places, '  ', TTextLines.LineBreakOf(Result)));
end;

{ TAtlasHiddenIndex }

constructor TAtlasHiddenIndex.Create(const APlaces: TArray<TAtlasHiddenPlace>; const AFolder: string);
var
  Place: TAtlasHiddenPlace;
  Name: string;
  List: TList<string>;
begin
  inherited Create;
  FFolder := AFolder;
  FAnchors := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  if AFolder = '' then
    Exit;
  for Place in APlaces do
  begin
    Name := LowerCase(Place.Setting + '|' + TAtlasHiddenPlaces.NormalizePath(Place.FileName));
    if not FAnchors.TryGetValue(Name, List) then
    begin
      List := TList<string>.Create;
      FAnchors.Add(Name, List);
    end;
    List.Add(Place.Anchor);
  end;
end;

destructor TAtlasHiddenIndex.Destroy;
begin
  FAnchors.Free;
  inherited Destroy;
end;

function TAtlasHiddenIndex.IsEmpty: Boolean;
begin
  Result := FAnchors.Count = 0;
end;

function TAtlasHiddenIndex.Lookup(const ASetting, AFileName: string; out AAnchors: TList<string>): Boolean;
begin
  AAnchors := nil;
  if FAnchors.Count = 0 then
    Exit(False);
  // Beim Zeichnen kommt dieselbe Datei Zeile für Zeile: Pfad nur einmal umrechnen.
  if AFileName <> FLastFile then
  begin
    FLastFile := AFileName;
    FLastInside := TAtlasHiddenPlaces.Relative(FFolder, AFileName, FLastRelative);
  end;
  Result := FLastInside and FAnchors.TryGetValue(LowerCase(ASetting + '|' + FLastRelative), AAnchors);
end;

function TAtlasHiddenIndex.FileHidden(const ASetting, AFileName: string): Boolean;
var
  Anchors: TList<string>;
begin
  Result := Lookup(ASetting, AFileName, Anchors) and Anchors.Contains('');
end;

function TAtlasHiddenIndex.Hidden(const ASetting, AFileName, AAnchor: string): Boolean;
var
  Anchors: TList<string>;
begin
  Result := Lookup(ASetting, AFileName, Anchors) and (Anchors.Contains('') or
    ((AAnchor <> '') and Anchors.Contains(AAnchor)));
end;

end.
