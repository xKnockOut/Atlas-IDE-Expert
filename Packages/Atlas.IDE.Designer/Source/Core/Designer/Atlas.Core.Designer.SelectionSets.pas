unit Atlas.Core.Designer.SelectionSets;

// Auswahlsätze im Designer (#739), ohne VCL und Windows: benannte Auswahlen
// je Formular, die sich per Menü oder Taste wiederherstellen lassen.
// - Je Formular (Schlüssel vom Aufrufer, z. B. der Dateipfad) eine geordnete
//   Liste; die ersten neun Sätze haben die Tasten 1…9 in dieser Reihenfolge.
// - Namensvorschlag aus dem gemeinsamen Wortteil der Komponentennamen
//   (edtAdresseStrasse, edtAdressePlz → „Adresse“), sonst leer.
// - Umbenannte Komponenten bleiben im Satz, gelöschte fallen heraus; ein
//   leerer Satz bleibt stehen.
// - Ablage als JSON {"version":1,"forms":{"<Schlüssel>":[{"name":…,
//   "members":[…]}]}}; die DFM bleibt unberührt.

interface

uses
  System.Generics.Collections;

type
  TAtlasSelectionSet = record
    Name: string;
    Members: TArray<string>;
    class function Create(const AName: string; const AMembers: TArray<string>): TAtlasSelectionSet; static;
  end;

  TAtlasSelectionSets = class
  public const
    /// <summary>Sätze mit Taste (1…9).</summary>
    cShortcutCount = 9;
  private
    FForms: TDictionary<string, TArray<TAtlasSelectionSet>>;
    FChanged: Boolean;
    function Key(const AForm: string): string;
    procedure Store(const AForm: string; const ASets: TArray<TAtlasSelectionSet>);
    function Valid(const AForm: string; AIndex: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function SetsOf(const AForm: string): TArray<TAtlasSelectionSet>;
    /// <summary>Neuer Satz am Ende; gibt es den Namen schon, ersetzt er dessen Mitglieder. Ergebnis: Index.
    /// </summary>
    function Add(const AForm, AName: string; const AMembers: TArray<string>): Integer;
    /// <summary>Mitglieder ersetzen („Mit aktueller Auswahl überschreiben“).</summary>
    procedure Replace(const AForm: string; AIndex: Integer; const AMembers: TArray<string>);
    /// <summary>Fehlende Mitglieder anhängen („Aktuelle Auswahl hinzufügen“).</summary>
    procedure Extend(const AForm: string; AIndex: Integer; const AMembers: TArray<string>);
    procedure Rename(const AForm: string; AIndex: Integer; const AName: string);
    procedure Delete(const AForm: string; AIndex: Integer);
    /// <summary>Satz um ADelta verschieben (−1 nach oben); ändert die Tasten.</summary>
    procedure Move(const AForm: string; AIndex, ADelta: Integer);
    /// <summary>Komponente umbenannt: in allen Sätzen des Formulars mitziehen.</summary>
    procedure ComponentRenamed(const AForm, AOldName, ANewName: string);
    /// <summary>Komponente gelöscht: aus allen Sätzen des Formulars entfernen.</summary>
    procedure ComponentDeleted(const AForm, AName: string);
    function ToJson: string;
    /// <summary>Ersetzt den Inhalt; False bei unbrauchbarem Text (Inhalt dann leer).</summary>
    function LoadJson(const AText: string): Boolean;
    /// <summary>Seit dem letzten Speichern geändert.</summary>
    property Changed: Boolean read FChanged write FChanged;
    /// <summary>Taste 1…9 des Satzes AIndex; 0 ohne.</summary>
    class function ShortcutOf(AIndex: Integer): Integer; static;
    /// <summary>Gemeinsamer Wortteil der Namen (ohne Kleinbuchstaben-Präfix wie edt); '' ohne.</summary>
    class function SuggestName(const AMembers: TArray<string>): string; static;
    /// <summary>Mitglieder von ASet, die in AExisting fehlen (ohne Groß-/Kleinschreibung).</summary>
    class function Missing(const ASet: TAtlasSelectionSet; const AExisting: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

{ TAtlasSelectionSet }

class function TAtlasSelectionSet.Create(const AName: string; const AMembers: TArray<string>): TAtlasSelectionSet;
begin
  Result.Name := AName;
  Result.Members := AMembers;
end;

function IndexOfText(const AList: TArray<string>; const AText: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AList) do
  begin
    if SameText(AList[mIndex], AText) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Namen ohne doppelte und leere Einträge, in der gegebenen Reihenfolge.</summary>
function Distinct(const ANames: TArray<string>): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    if (mName <> '') and (IndexOfText(Result, mName) < 0) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

{ TAtlasSelectionSets }

constructor TAtlasSelectionSets.Create;
begin
  inherited Create;
  FForms := TDictionary<string, TArray<TAtlasSelectionSet>>.Create;
end;

destructor TAtlasSelectionSets.Destroy;
begin
  FForms.Free;
  inherited Destroy;
end;

function TAtlasSelectionSets.Key(const AForm: string): string;
begin
  Result := UpperCase(AForm);
end;

procedure TAtlasSelectionSets.Store(const AForm: string; const ASets: TArray<TAtlasSelectionSet>);
begin
  if Length(ASets) = 0 then
  begin
    FForms.Remove(Key(AForm));
  end
  else
  begin
    FForms.AddOrSetValue(Key(AForm), ASets);
  end;
  FChanged := True;
end;

function TAtlasSelectionSets.Valid(const AForm: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(SetsOf(AForm)));
end;

function TAtlasSelectionSets.SetsOf(const AForm: string): TArray<TAtlasSelectionSet>;
begin
  if not FForms.TryGetValue(Key(AForm), Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasSelectionSets.Add(const AForm, AName: string; const AMembers: TArray<string>): Integer;
var
  mSets: TArray<TAtlasSelectionSet>;
  mIndex: Integer;
begin
  mSets := SetsOf(AForm);
  for mIndex := 0 to High(mSets) do
  begin
    if SameText(mSets[mIndex].Name, Trim(AName)) then
    begin
      mSets[mIndex].Members := Distinct(AMembers);
      Store(AForm, mSets);
      Exit(mIndex);
    end;
  end;
  mSets := mSets + [TAtlasSelectionSet.Create(Trim(AName), Distinct(AMembers))];
  Store(AForm, mSets);
  Result := High(mSets);
end;

procedure TAtlasSelectionSets.Replace(const AForm: string; AIndex: Integer; const AMembers: TArray<string>);
var
  mSets: TArray<TAtlasSelectionSet>;
begin
  if not Valid(AForm, AIndex) then
  begin
    Exit;
  end;
  mSets := SetsOf(AForm);
  mSets[AIndex].Members := Distinct(AMembers);
  Store(AForm, mSets);
end;

procedure TAtlasSelectionSets.Extend(const AForm: string; AIndex: Integer; const AMembers: TArray<string>);
var
  mSets: TArray<TAtlasSelectionSet>;
begin
  if not Valid(AForm, AIndex) then
  begin
    Exit;
  end;
  mSets := SetsOf(AForm);
  mSets[AIndex].Members := Distinct(mSets[AIndex].Members + AMembers);
  Store(AForm, mSets);
end;

procedure TAtlasSelectionSets.Rename(const AForm: string; AIndex: Integer; const AName: string);
var
  mSets: TArray<TAtlasSelectionSet>;
begin
  if not Valid(AForm, AIndex) or (Trim(AName) = '') then
  begin
    Exit;
  end;
  mSets := SetsOf(AForm);
  mSets[AIndex].Name := Trim(AName);
  Store(AForm, mSets);
end;

procedure TAtlasSelectionSets.Delete(const AForm: string; AIndex: Integer);
var
  mSets: TArray<TAtlasSelectionSet>;
begin
  if not Valid(AForm, AIndex) then
  begin
    Exit;
  end;
  mSets := SetsOf(AForm);
  System.Delete(mSets, AIndex, 1);
  Store(AForm, mSets);
end;

procedure TAtlasSelectionSets.Move(const AForm: string; AIndex, ADelta: Integer);
var
  mSets: TArray<TAtlasSelectionSet>;
  mTarget: Integer;
  mSet: TAtlasSelectionSet;
begin
  mTarget := AIndex + ADelta;
  if not Valid(AForm, AIndex) or not Valid(AForm, mTarget) or (ADelta = 0) then
  begin
    Exit;
  end;
  mSets := SetsOf(AForm);
  mSet := mSets[AIndex];
  System.Delete(mSets, AIndex, 1);
  Insert(mSet, mSets, mTarget);
  Store(AForm, mSets);
end;

procedure TAtlasSelectionSets.ComponentRenamed(const AForm, AOldName, ANewName: string);
var
  mSets: TArray<TAtlasSelectionSet>;
  mIndex, mMember: Integer;
  mFound: Boolean;
begin
  mSets := SetsOf(AForm);
  mFound := False;
  for mIndex := 0 to High(mSets) do
  begin
    mMember := IndexOfText(mSets[mIndex].Members, AOldName);
    if mMember >= 0 then
    begin
      mSets[mIndex].Members[mMember] := ANewName;
      mSets[mIndex].Members := Distinct(mSets[mIndex].Members);
      mFound := True;
    end;
  end;
  if mFound then
  begin
    Store(AForm, mSets);
  end;
end;

procedure TAtlasSelectionSets.ComponentDeleted(const AForm, AName: string);
var
  mSets: TArray<TAtlasSelectionSet>;
  mIndex, mMember: Integer;
  mFound: Boolean;
begin
  mSets := SetsOf(AForm);
  mFound := False;
  for mIndex := 0 to High(mSets) do
  begin
    mMember := IndexOfText(mSets[mIndex].Members, AName);
    if mMember >= 0 then
    begin
      System.Delete(mSets[mIndex].Members, mMember, 1);
      mFound := True;
    end;
  end;
  if mFound then
  begin
    Store(AForm, mSets);
  end;
end;

function TAtlasSelectionSets.ToJson: string;
var
  mRoot, mForms, mItem: TJSONObject;
  mList, mMembers: TJSONArray;
  mPair: TPair<string, TArray<TAtlasSelectionSet>>;
  mSet: TAtlasSelectionSet;
  mMember: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(1));
    mForms := TJSONObject.Create;
    mRoot.AddPair('forms', mForms);
    for mPair in FForms do
    begin
      mList := TJSONArray.Create;
      mForms.AddPair(mPair.Key, mList);
      for mSet in mPair.Value do
      begin
        mItem := TJSONObject.Create;
        mList.AddElement(mItem);
        mItem.AddPair('name', mSet.Name);
        mMembers := TJSONArray.Create;
        mItem.AddPair('members', mMembers);
        for mMember in mSet.Members do
        begin
          mMembers.Add(mMember);
        end;
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Sätze aus einem JSON-Array; unbrauchbare Einträge fallen weg.</summary>
function SetsFromJson(AList: TJSONArray): TArray<TAtlasSelectionSet>;
var
  mValue, mMember: TJSONValue;
  mName: string;
  mMembers: TJSONArray;
  mNames: TArray<string>;
begin
  Result := nil;
  for mValue in AList do
  begin
    if not (mValue is TJSONObject) or not TJSONObject(mValue).TryGetValue<string>('name', mName) or
      (Trim(mName) = '') then
    begin
      Continue;
    end;
    mNames := nil;
    if TJSONObject(mValue).TryGetValue<TJSONArray>('members', mMembers) then
    begin
      for mMember in mMembers do
      begin
        // TJSONNumber erbt von TJSONString: Zahlen sind keine Namen.
        if (mMember is TJSONString) and not (mMember is TJSONNumber) then
        begin
          mNames := mNames + [TJSONString(mMember).Value];
        end;
      end;
    end;
    Result := Result + [TAtlasSelectionSet.Create(mName, Distinct(mNames))];
  end;
end;

function TAtlasSelectionSets.LoadJson(const AText: string): Boolean;
var
  mRoot: TJSONValue;
  mForms: TJSONObject;
  mPair: TJSONPair;
  mSets: TArray<TAtlasSelectionSet>;
begin
  FForms.Clear;
  FChanged := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<TJSONObject>('forms', mForms);
    if not Result then
    begin
      Exit;
    end;
    for mPair in mForms do
    begin
      if mPair.JsonValue is TJSONArray then
      begin
        mSets := SetsFromJson(TJSONArray(mPair.JsonValue));
        if Length(mSets) > 0 then
        begin
          FForms.AddOrSetValue(Key(mPair.JsonString.Value), mSets);
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasSelectionSets.ShortcutOf(AIndex: Integer): Integer;
begin
  Result := 0;
  if (AIndex >= 0) and (AIndex < cShortcutCount) then
  begin
    Result := AIndex + 1;
  end;
end;

/// <summary>Wörter eines Namens: Kleinbuchstaben-Präfix (edt, btn) weg, dann an Großbuchstaben, Ziffern und „_“
/// getrennt.</summary>
function WordsOf(const AName: string): TArray<string>;
var
  mIndex: Integer;
  mWord: string;
  mChar: Char;
begin
  Result := nil;
  mIndex := 1;
  // Präfix: führende Kleinbuchstaben, sofern danach noch etwas kommt.
  while (mIndex <= Length(AName)) and CharInSet(AName[mIndex], ['a'..'z']) do
  begin
    Inc(mIndex);
  end;
  if mIndex > Length(AName) then
  begin
    mIndex := 1;
  end;
  mWord := '';
  while mIndex <= Length(AName) do
  begin
    mChar := AName[mIndex];
    if CharInSet(mChar, ['A'..'Z', '_', '0'..'9']) and (mWord <> '') then
    begin
      Result := Result + [mWord];
      mWord := '';
    end;
    if not CharInSet(mChar, ['_', '0'..'9']) then
    begin
      mWord := mWord + mChar;
    end;
    Inc(mIndex);
  end;
  if mWord <> '' then
  begin
    Result := Result + [mWord];
  end;
end;

class function TAtlasSelectionSets.SuggestName(const AMembers: TArray<string>): string;
var
  mWord, mMember: string;
  mCommon: Boolean;
begin
  Result := '';
  if Length(AMembers) < 2 then
  begin
    Exit;
  end;
  for mWord in WordsOf(AMembers[0]) do
  begin
    mCommon := True;
    for mMember in AMembers do
    begin
      if IndexOfText(WordsOf(mMember), mWord) < 0 then
      begin
        mCommon := False;
        Break;
      end;
    end;
    if mCommon then
    begin
      Exit(mWord);
    end;
  end;
end;

class function TAtlasSelectionSets.Missing(const ASet: TAtlasSelectionSet;
  const AExisting: TArray<string>): TArray<string>;
var
  mMember: string;
begin
  Result := nil;
  for mMember in ASet.Members do
  begin
    if IndexOfText(AExisting, mMember) < 0 then
    begin
      Result := Result + [mMember];
    end;
  end;
end;

end.
