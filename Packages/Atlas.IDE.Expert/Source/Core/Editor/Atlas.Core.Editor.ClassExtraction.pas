unit Atlas.Core.Editor.ClassExtraction;

// Eingabemaske „Mitglieder herauslösen“ ohne VCL, gemeinsam für „Interface
// herauslösen“ (#664) und „Basisklasse herauslösen“ (#713): die Kandidaten
// aus der Antwort von prepare (mit Häkchen, gesperrten Einträgen samt Grund),
// Name und Ziel-Unit des neuen Typs, die Prüfung vor dem Absenden und das
// JSON für den Server ({name, unit, members, abstract}). Für die Basisklasse
// kommen dazu: Methoden nur abstrakt nach oben (canAbstract/abstract), die
// Abhängigkeiten der Mitglieder (needs) mit Prüfung und „Abhängigkeiten
// mitnehmen“ und das voreingestellte Ziel (unit). Die Prüfung liefert die Art
// des Fehlers, den Text wählt die Oberfläche in ihrer Sprache.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Erster Fehler der Eingabe.</summary>
  TAtlasExtractionProblem = (None, BadName, SameName, NoMembers, BadUnit, MissingDependency);
  {$SCOPEDENUMS OFF}

  TAtlasExtractionMember = record
    /// <summary>Kennung für den Server (Stelle des Mitglieds in der Klasse).</summary>
    Id: Integer;
    Name: string;
    /// <summary>'field', 'method' oder 'property'.</summary>
    Kind: string;
    /// <summary>Deklaration zur Anzeige.</summary>
    Display: string;
    Visibility: string;
    Checked: Boolean;
    Enabled: Boolean;
    /// <summary>Warum gesperrt bzw. was beim Herauslösen geschieht; '' ohne.</summary>
    Reason: string;
    /// <summary>Darf als abstrakte Methode nach oben (#713).</summary>
    CanAbstract: Boolean;
    /// <summary>Nur die Deklaration wandert als abstrakt nach oben, der Rumpf bleibt.</summary>
    Abstract: Boolean;
    /// <summary>Kennungen der Mitglieder, die dieses benutzt (#713).</summary>
    Needs: TArray<Integer>;
  end;

  TAtlasClassExtractionModel = class
  private
    FSourceClass: string;
    FOwnUnit: string;
    FName: string;
    FTargetUnit: string;
    FUnits: TArray<string>;
    FNotes: TArray<string>;
    FMembers: TArray<TAtlasExtractionMember>;
    function GetMember(AIndex: Integer): TAtlasExtractionMember;
    function GetCount: Integer;
    function IndexOfId(AId: Integer): Integer;
  public
    /// <summary>Aus der Antwort von prepare ({className, ownUnit, name, candidates, notes, units}).</summary>
    constructor Create(const APrepared: TJSONObject);
    /// <summary>Häkchen setzen; gesperrte Einträge bleiben, wie sie sind.</summary>
    procedure SetChecked(AIndex: Integer; AChecked: Boolean);
    /// <summary>Alle wählbaren Einträge an- bzw. abhaken.</summary>
    procedure CheckAll(AChecked: Boolean);
    function CheckedCount: Integer;
    /// <summary>Methode nur abstrakt nach oben bzw. ganz verschieben; ohne Wirkung, wenn sie nicht abstrakt sein
    /// darf.</summary>
    procedure SetAbstract(AIndex: Integer; AAbstract: Boolean);
    /// <summary>Hat ein Kandidat die Wahl „abstrakt“?</summary>
    function HasModes: Boolean;
    /// <summary>Hat ein Kandidat Abhängigkeiten?</summary>
    function HasNeeds: Boolean;
    /// <summary>Erstes gewähltes, ganz wanderndes Mitglied AMember, das ANeeded benutzt, ohne dass ANeeded
    /// mitwandert; False ohne solches.</summary>
    function MissingDependency(out AMember, ANeeded: string): Boolean;
    /// <summary>Hakt alles an, was die gewählten, ganz wandernden Mitglieder benutzen (auch über mehrere
    /// Stufen); liefert die Zahl neu angehakter Einträge.</summary>
    function TakeDependencies: Integer;
    /// <summary>Erster Fehler (Name, gleicher Name wie die Klasse, kein Mitglied, Unit-Name, fehlende
    /// Abhängigkeit); ASubject: betroffener Name (bei der Abhängigkeit das benutzende Mitglied).</summary>
    function Validate(out ASubject: string): TAtlasExtractionProblem; overload;
    function Validate: TAtlasExtractionProblem; overload;
    /// <summary>Argument für den Server: {name, unit, members} und abstract mit den nur abstrakt wandernden
    /// Methoden, wenn es welche gibt; unit '' = dieselbe Unit. Der Aufrufer übernimmt das Objekt.</summary>
    function RequestJson: TJSONObject;
    /// <summary>Ziel-Unit für den Server; '' = die Unit der Klasse (auch wenn ihr Name eingetragen ist).</summary>
    function Target: string;
    property SourceClass: string read FSourceClass;
    /// <summary>Unit der Klasse.</summary>
    property OwnUnit: string read FOwnUnit;
    property Name: string read FName write FName;
    /// <summary>Ziel-Unit; '' = die Unit der Klasse. Vorbelegt aus prepare (unit).</summary>
    property TargetUnit: string read FTargetUnit write FTargetUnit;
    /// <summary>Units des Projekts für die Auswahl.</summary>
    property Units: TArray<string> read FUnits;
    property Notes: TArray<string> read FNotes;
    property Members[AIndex: Integer]: TAtlasExtractionMember read GetMember; default;
    property Count: Integer read GetCount;
  end;

implementation

uses
  Atlas.Core.Editor.LinkedEditing;

function IsName(const AName: string): Boolean;
begin
  Result := IsValidIdent(AName) and not TAtlasLinkedEditing.IsReserved(AName);
end;

/// <summary>Unit-Name mit Punkten, jeder Teil ein Bezeichner.</summary>
function IsUnitName(const AName: string): Boolean;
var
  Part: string;
begin
  Result := AName <> '';
  for Part in AName.Split(['.']) do
    if not IsValidIdent(Part) then
      Exit(False);
end;

function StringOf(AObject: TJSONObject; const AKey: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AKey);
  if (Value <> nil) and not (Value is TJSONNull) then
    Result := Value.Value;
end;

function BoolOf(AObject: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AKey);
  if Value is TJSONBool then
    Result := TJSONBool(Value).AsBoolean
  else
    Result := ADefault;
end;

function IdsOf(AObject: TJSONObject; const AKey: string): TArray<Integer>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
    for Item in TJSONArray(Value) do
      if Item is TJSONNumber then
        Result := Result + [TJSONNumber(Item).AsInt];
end;

function StringsOf(AObject: TJSONObject; const AKey: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
    for Item in TJSONArray(Value) do
      Result := Result + [Item.Value];
end;

{ TAtlasClassExtractionModel }

constructor TAtlasClassExtractionModel.Create(const APrepared: TJSONObject);
var
  Value, Item: TJSONValue;
  Member: TAtlasExtractionMember;
  Entry: TJSONObject;
begin
  inherited Create;
  FSourceClass := StringOf(APrepared, 'className');
  FOwnUnit := StringOf(APrepared, 'ownUnit');
  FName := StringOf(APrepared, 'name');
  FNotes := StringsOf(APrepared, 'notes');
  FUnits := StringsOf(APrepared, 'units');
  FTargetUnit := StringOf(APrepared, 'unit');
  if APrepared = nil then
    Exit;
  Value := APrepared.GetValue('candidates');
  if not (Value is TJSONArray) then
    Exit;
  for Item in TJSONArray(Value) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Entry := TJSONObject(Item);
    Member := Default(TAtlasExtractionMember);
    if Entry.GetValue('id') is TJSONNumber then
      Member.Id := TJSONNumber(Entry.GetValue('id')).AsInt;
    Member.Name := StringOf(Entry, 'name');
    Member.Kind := StringOf(Entry, 'kind');
    Member.Display := StringOf(Entry, 'display');
    Member.Visibility := StringOf(Entry, 'visibility');
    Member.Enabled := BoolOf(Entry, 'enabled', True);
    Member.Checked := BoolOf(Entry, 'checked', False) and Member.Enabled;
    Member.Reason := StringOf(Entry, 'reason');
    Member.CanAbstract := BoolOf(Entry, 'canAbstract', False) and Member.Enabled;
    Member.Abstract := BoolOf(Entry, 'abstract', False) and Member.CanAbstract;
    Member.Needs := IdsOf(Entry, 'needs');
    FMembers := FMembers + [Member];
  end;
end;

function TAtlasClassExtractionModel.GetMember(AIndex: Integer): TAtlasExtractionMember;
begin
  Result := FMembers[AIndex];
end;

function TAtlasClassExtractionModel.GetCount: Integer;
begin
  Result := Length(FMembers);
end;

function TAtlasClassExtractionModel.IndexOfId(AId: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(FMembers) do
    if FMembers[Index].Id = AId then
      Exit(Index);
end;

procedure TAtlasClassExtractionModel.SetChecked(AIndex: Integer; AChecked: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FMembers)) or not FMembers[AIndex].Enabled then
    Exit;
  FMembers[AIndex].Checked := AChecked;
end;

procedure TAtlasClassExtractionModel.CheckAll(AChecked: Boolean);
var
  Index: Integer;
begin
  for Index := 0 to High(FMembers) do
    SetChecked(Index, AChecked);
end;

function TAtlasClassExtractionModel.CheckedCount: Integer;
var
  Member: TAtlasExtractionMember;
begin
  Result := 0;
  for Member in FMembers do
    if Member.Checked then
      Inc(Result);
end;

procedure TAtlasClassExtractionModel.SetAbstract(AIndex: Integer; AAbstract: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FMembers)) or not FMembers[AIndex].CanAbstract then
    Exit;
  FMembers[AIndex].Abstract := AAbstract;
end;

function TAtlasClassExtractionModel.HasModes: Boolean;
var
  Member: TAtlasExtractionMember;
begin
  Result := False;
  for Member in FMembers do
    if Member.CanAbstract then
      Exit(True);
end;

function TAtlasClassExtractionModel.HasNeeds: Boolean;
var
  Member: TAtlasExtractionMember;
begin
  Result := False;
  for Member in FMembers do
    if Member.Needs <> nil then
      Exit(True);
end;

function TAtlasClassExtractionModel.MissingDependency(out AMember, ANeeded: string): Boolean;
var
  Member: TAtlasExtractionMember;
  Need, Index: Integer;
begin
  AMember := '';
  ANeeded := '';
  // Eine abstrakte Methode nimmt ihren Rumpf nicht mit und braucht oben nichts.
  for Member in FMembers do
    if Member.Checked and not Member.Abstract then
      for Need in Member.Needs do
      begin
        Index := IndexOfId(Need);
        if (Index >= 0) and not FMembers[Index].Checked then
        begin
          AMember := Member.Name;
          ANeeded := FMembers[Index].Name;
          Exit(True);
        end;
      end;
  Result := False;
end;

function TAtlasClassExtractionModel.TakeDependencies: Integer;
var
  Index, Need, Needed: Integer;
  Changed: Boolean;
begin
  Result := 0;
  repeat
    Changed := False;
    for Index := 0 to High(FMembers) do
      if FMembers[Index].Checked and not FMembers[Index].Abstract then
        for Need in FMembers[Index].Needs do
        begin
          Needed := IndexOfId(Need);
          if (Needed >= 0) and FMembers[Needed].Enabled and not FMembers[Needed].Checked then
          begin
            FMembers[Needed].Checked := True;
            Inc(Result);
            Changed := True;
          end;
        end;
  until not Changed;
end;

function TAtlasClassExtractionModel.Validate(out ASubject: string): TAtlasExtractionProblem;
var
  Candidate, Needed: string;
begin
  Candidate := Trim(FName);
  ASubject := Candidate;
  if not IsName(Candidate) then
    Exit(TAtlasExtractionProblem.BadName);
  if SameText(Candidate, FSourceClass) then
    Exit(TAtlasExtractionProblem.SameName);
  if CheckedCount = 0 then
  begin
    ASubject := '';
    Exit(TAtlasExtractionProblem.NoMembers);
  end;
  if MissingDependency(Candidate, Needed) then
  begin
    ASubject := Candidate;
    Exit(TAtlasExtractionProblem.MissingDependency);
  end;
  Candidate := Target;
  if (Candidate <> '') and not IsUnitName(Candidate) then
  begin
    ASubject := Candidate;
    Exit(TAtlasExtractionProblem.BadUnit);
  end;
  ASubject := '';
  Result := TAtlasExtractionProblem.None;
end;

function TAtlasClassExtractionModel.Validate: TAtlasExtractionProblem;
var
  Subject: string;
begin
  Result := Validate(Subject);
end;

function TAtlasClassExtractionModel.Target: string;
begin
  Result := Trim(FTargetUnit);
  if SameText(Result, FOwnUnit) then
    Result := '';
end;

function TAtlasClassExtractionModel.RequestJson: TJSONObject;
var
  List, Abstracts: TJSONArray;
  Member: TAtlasExtractionMember;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Trim(FName));
  Result.AddPair('unit', Target);
  List := TJSONArray.Create;
  for Member in FMembers do
    if Member.Checked then
      List.AddElement(TJSONNumber.Create(Member.Id));
  Result.AddPair('members', List);
  Abstracts := nil;
  for Member in FMembers do
    if Member.Checked and Member.Abstract then
    begin
      if Abstracts = nil then
        Abstracts := TJSONArray.Create;
      Abstracts.AddElement(TJSONNumber.Create(Member.Id));
    end;
  if Abstracts <> nil then
    Result.AddPair('abstract', Abstracts);
end;

end.
