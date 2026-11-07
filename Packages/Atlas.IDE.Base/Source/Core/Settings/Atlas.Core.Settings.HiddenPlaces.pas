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
  mIndex: Integer;
begin
  Result := Trim(APath);
  for mIndex := 1 to Length(Result) do
  begin
    if Result[mIndex] = '\' then
    begin
      Result[mIndex] := '/';
    end;
  end;
  while Result.StartsWith('./') do
  begin
    Result := Copy(Result, 3, MaxInt);
  end;
end;

class function TAtlasHiddenPlaces.Relative(const AFolder, AFileName: string; out ARelative: string): Boolean;
var
  mFolder, mFileName: string;
begin
  ARelative := '';
  mFolder := NormalizePath(AFolder);
  while (mFolder <> '') and IsSeparator(mFolder[Length(mFolder)]) do
  begin
    Delete(mFolder, Length(mFolder), 1);
  end;
  mFileName := NormalizePath(AFileName);
  Result := (mFolder <> '') and (Length(mFileName) > Length(mFolder) + 1) and
    SameText(Copy(mFileName, 1, Length(mFolder)), mFolder) and (mFileName[Length(mFolder) + 1] = '/');
  if Result then
  begin
    ARelative := Copy(mFileName, Length(mFolder) + 2, MaxInt);
  end;
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
  mIndex: Integer;
begin
  for mIndex := 0 to High(APlaces) do
  begin
    if APlaces[mIndex].SameAs(APlace) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasHiddenPlaces.ToJson(const APlaces: TArray<TAtlasHiddenPlace>;
  const AIndent, ALineBreak: string): string;
var
  mIndex: Integer;
  mItem: string;
begin
  if Length(APlaces) = 0 then
  begin
    Exit('[]');
  end;
  Result := '[';
  for mIndex := 0 to High(APlaces) do
  begin
    mItem := '{"setting": ' + TAtlasJsonText.Quote(APlaces[mIndex].Setting) + ', "file": ' +
      TAtlasJsonText.Quote(NormalizePath(APlaces[mIndex].FileName));
    if APlaces[mIndex].Anchor <> '' then
    begin
      mItem := mItem + ', "anchor": ' + TAtlasJsonText.Quote(APlaces[mIndex].Anchor);
    end;
    mItem := mItem + '}';
    if mIndex < High(APlaces) then
    begin
      mItem := mItem + ',';
    end;
    Result := Result + ALineBreak + AIndent + '  ' + mItem;
  end;
  Result := Result + ALineBreak + AIndent + ']';
end;

class function TAtlasHiddenPlaces.FromText(const AText: string): TArray<TAtlasHiddenPlace>;
var
  mRoot: TJSONObject;
  mValue, mItem: TJSONValue;
  mPlace: TAtlasHiddenPlace;
begin
  Result := nil;
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    mValue := mRoot.GetValue(Key);
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mPlace := TAtlasHiddenPlace.Create(TJSONObject(mItem).GetValue<string>('setting', ''),
        TJSONObject(mItem).GetValue<string>('file', ''), TJSONObject(mItem).GetValue<string>('anchor', ''));
      if (mPlace.Setting <> '') and (mPlace.FileName <> '') then
      begin
        Result := Result + [mPlace];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasHiddenPlaces.AddTo(const AText, ASkeleton: string; const APlace: TAtlasHiddenPlace): string;
var
  mPlaces: TArray<TAtlasHiddenPlace>;
begin
  Result := AText;
  if Trim(Result) = '' then
  begin
    Result := ASkeleton;
  end;
  mPlaces := FromText(Result);
  if IndexOf(mPlaces, APlace) >= 0 then
  begin
    Exit;
  end;
  mPlaces := mPlaces + [APlace];
  Result := TAtlasJsonText.SetValue(Result, Key, ToJson(mPlaces, '  ', TTextLines.LineBreakOf(Result)));
end;

class function TAtlasHiddenPlaces.RemoveFrom(const AText: string; const APlace: TAtlasHiddenPlace): string;
var
  mPlaces: TArray<TAtlasHiddenPlace>;
  mIndex: Integer;
begin
  Result := AText;
  mPlaces := FromText(Result);
  mIndex := IndexOf(mPlaces, APlace);
  if mIndex < 0 then
  begin
    Exit;
  end;
  Delete(mPlaces, mIndex, 1);
  Result := TAtlasJsonText.SetValue(Result, Key, ToJson(mPlaces, '  ', TTextLines.LineBreakOf(Result)));
end;

{ TAtlasHiddenIndex }

constructor TAtlasHiddenIndex.Create(const APlaces: TArray<TAtlasHiddenPlace>; const AFolder: string);
var
  mPlace: TAtlasHiddenPlace;
  mName: string;
  mList: TList<string>;
begin
  inherited Create;
  FFolder := AFolder;
  FAnchors := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  if AFolder = '' then
  begin
    Exit;
  end;
  for mPlace in APlaces do
  begin
    mName := LowerCase(mPlace.Setting + '|' + TAtlasHiddenPlaces.NormalizePath(mPlace.FileName));
    if not FAnchors.TryGetValue(mName, mList) then
    begin
      mList := TList<string>.Create;
      FAnchors.Add(mName, mList);
    end;
    mList.Add(mPlace.Anchor);
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
  begin
    Exit(False);
  end;
  // Beim Zeichnen kommt dieselbe Datei Zeile für Zeile: Pfad nur einmal umrechnen.
  if not SameFileName(AFileName, FLastFile) then
  begin
    FLastFile := AFileName;
    FLastInside := TAtlasHiddenPlaces.Relative(FFolder, AFileName, FLastRelative);
  end;
  Result := FLastInside and FAnchors.TryGetValue(LowerCase(ASetting + '|' + FLastRelative), AAnchors);
end;

function TAtlasHiddenIndex.FileHidden(const ASetting, AFileName: string): Boolean;
var
  mAnchors: TList<string>;
begin
  Result := Lookup(ASetting, AFileName, mAnchors) and mAnchors.Contains('');
end;

function TAtlasHiddenIndex.Hidden(const ASetting, AFileName, AAnchor: string): Boolean;
var
  mAnchors: TList<string>;
begin
  Result := Lookup(ASetting, AFileName, mAnchors) and (mAnchors.Contains('') or
    ((AAnchor <> '') and mAnchors.Contains(AAnchor)));
end;

end.
