unit Atlas.Core.Editor.ClassExtraction;

// Eingabemaske „Mitglieder herauslösen“ ohne VCL, gemeinsam für „Interface
// herauslösen“ (#664) und „Basisklasse herauslösen“ (#713): die Kandidaten
// aus der Antwort von prepare (mit Häkchen, gesperrten Einträgen samt Grund),
// Name und Ziel-Unit des neuen Typs, die Prüfung vor dem Absenden und das
// JSON für den Server ({name, unit, members, abstract}). Für die Basisklasse
// kommen dazu: Methoden nur abstrakt nach oben (canAbstract/abstract), die
// Abhängigkeiten der Mitglieder (needs) mit Prüfung und „Abhängigkeiten
// mitnehmen“ und das voreingestellte Ziel (unit). Für „Mitglied verschieben“
// (#675) statt Name und Unit die Ziele (targets: ein Vorfahr bzw. mehrere
// Nachfahren), eine Wahl (option: andere Nachfahren überschreiben bzw.
// abstrakt im Vorfahren lassen) und ob Abhängigkeiten Pflicht sind
// (needsRequired); das JSON ist dann {members, abstract, targets, option}.
// Die Prüfung liefert die Art des Fehlers, den Text wählt die Oberfläche in
// ihrer Sprache.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Erster Fehler der Eingabe.</summary>
  TAtlasExtractionProblem = (None, BadName, SameName, NoMembers, BadUnit, MissingDependency, NoTarget);
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

  /// <summary>Ziel von „Mitglied verschieben“: Klasse und ihre Unit.</summary>
  TAtlasExtractionTarget = record
    Name: string;
    UnitName: string;
    Checked: Boolean;
  end;

  /// <summary>Was prepare über die Klasse und den Aufruf meldet; ändert sich in der Maske nicht.</summary>
  TAtlasExtractionSource = record
    SourceClass: string;
    /// <summary>Unit der Klasse.</summary>
    OwnUnit: string;
    /// <summary>Units des Projekts für die Auswahl.</summary>
    Units: TArray<string>;
    Notes: TArray<string>;
    /// <summary>Mitglied an der Stelle der Code-Aktion (#675); '' sonst.</summary>
    MemberName: string;
    /// <summary>'up' oder 'down' (#675); '' sonst.</summary>
    Direction: string;
    /// <summary>Mehrere Ziele wählbar (Nachfahren).</summary>
    MultiTarget: Boolean;
    /// <summary>Fehlende Abhängigkeiten sperren das Absenden.</summary>
    NeedsRequired: Boolean;
    /// <summary>'overrideSiblings', 'keepAbstract' oder '' ohne Wahl.</summary>
    OptionKind: string;
  end;

  TAtlasClassExtractionModel = class
  private
    FSource: TAtlasExtractionSource;
    FName: string;
    FTargetUnit: string;
    FMembers: TArray<TAtlasExtractionMember>;
    FTargets: TArray<TAtlasExtractionTarget>;
    FOption: Boolean;
    function GetMember(AIndex: Integer): TAtlasExtractionMember;
    function GetCount: Integer;
    function IndexOfId(AId: Integer): Integer;
    function GetTarget(AIndex: Integer): TAtlasExtractionTarget;
    function GetTargetCount: Integer;
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
    /// <summary>„Mitglied verschieben“: Ziele statt Name und Unit.</summary>
    function IsMove: Boolean;
    /// <summary>Ziel an- bzw. abhaken; mit nur einem Ziel wählt es dieses allein.</summary>
    procedure SetTargetChecked(AIndex: Integer; AChecked: Boolean);
    /// <summary>Namen der gewählten Ziele.</summary>
    function CheckedTargets: TArray<string>;
    /// <summary>Klasse, Units, Hinweise und Art des Aufrufs aus prepare.</summary>
    property Source: TAtlasExtractionSource read FSource;
    property Name: string read FName write FName;
    /// <summary>Ziel-Unit; '' = die Unit der Klasse. Vorbelegt aus prepare (unit).</summary>
    property TargetUnit: string read FTargetUnit write FTargetUnit;
    property Members[AIndex: Integer]: TAtlasExtractionMember read GetMember; default;
    property Count: Integer read GetCount;
    property Targets[AIndex: Integer]: TAtlasExtractionTarget read GetTarget;
    property TargetCount: Integer read GetTargetCount;
    property Option: Boolean read FOption write FOption;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Editor.LinkedEditing,
  Atlas.Text.Json;

function IsName(const AName: string): Boolean;
begin
  Result := IsValidIdent(AName) and not TAtlasLinkedEditing.IsReserved(AName);
end;

/// <summary>Unit-Name mit Punkten, jeder Teil ein Bezeichner.</summary>
function IsUnitName(const AName: string): Boolean;
var
  mPart: string;
begin
  Result := AName <> '';
  for mPart in AName.Split(['.']) do
  begin
    if not IsValidIdent(mPart) then
    begin
      Exit(False);
    end;
  end;
end;

function StringOf(AObject: TJSONObject; const AKey: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AKey);
  if (mValue <> nil) and not (mValue is TJSONNull) then
  begin
    Result := mValue.Value;
  end;
end;

function IdsOf(AObject: TJSONObject; const AKey: string): TArray<Integer>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AObject.GetValue(AKey);
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      if mItem is TJSONNumber then
      begin
        Result := Result + [TJSONNumber(mItem).AsInt];
      end;
    end;
  end;
end;

function StringsOf(AObject: TJSONObject; const AKey: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AKey);
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

{ TAtlasClassExtractionModel }

/// <summary>Option aus prepare ({kind, value}); nil, wenn keine angeboten wird.</summary>
function OptionOf(APrepared: TJSONObject): TJSONObject;
begin
  Result := nil;
  if (APrepared <> nil) and (APrepared.GetValue('option') is TJSONObject) then
  begin
    Result := TJSONObject(APrepared.GetValue('option'));
  end;
end;

function ReadSource(APrepared: TJSONObject): TAtlasExtractionSource;
begin
  Result := Default(TAtlasExtractionSource);
  Result.SourceClass := StringOf(APrepared, 'className');
  Result.OwnUnit := StringOf(APrepared, 'ownUnit');
  Result.Notes := StringsOf(APrepared, 'notes');
  Result.Units := StringsOf(APrepared, 'units');
  Result.MemberName := StringOf(APrepared, 'member');
  Result.Direction := StringOf(APrepared, 'direction');
  Result.NeedsRequired := TJsonRead.FlagOr(APrepared, 'needsRequired', True);
  Result.MultiTarget := TJsonRead.FlagOr(APrepared, 'multiTarget', False);
  Result.OptionKind := StringOf(OptionOf(APrepared), 'kind');
end;

/// <summary>Einträge der Liste AKey, die Objekte sind.</summary>
function ObjectsOf(APrepared: TJSONObject; const AKey: string): TArray<TJSONObject>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if (APrepared <> nil) and (APrepared.GetValue(AKey) is TJSONArray) then
  begin
    for mItem in TJSONArray(APrepared.GetValue(AKey)) do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + [TJSONObject(mItem)];
      end;
    end;
  end;
end;

function ReadTargets(APrepared: TJSONObject): TArray<TAtlasExtractionTarget>;
var
  mEntry: TJSONObject;
  mTarget: TAtlasExtractionTarget;
begin
  Result := nil;
  for mEntry in ObjectsOf(APrepared, 'targets') do
  begin
    mTarget := Default(TAtlasExtractionTarget);
    mTarget.Name := StringOf(mEntry, 'name');
    mTarget.UnitName := StringOf(mEntry, 'unit');
    mTarget.Checked := TJsonRead.FlagOr(mEntry, 'checked', False);
    Result := Result + [mTarget];
  end;
end;

function ReadMember(AEntry: TJSONObject): TAtlasExtractionMember;
begin
  Result := Default(TAtlasExtractionMember);
  if AEntry.GetValue('id') is TJSONNumber then
  begin
    Result.Id := TJSONNumber(AEntry.GetValue('id')).AsInt;
  end;
  Result.Name := StringOf(AEntry, 'name');
  Result.Kind := StringOf(AEntry, 'kind');
  Result.Display := StringOf(AEntry, 'display');
  Result.Visibility := StringOf(AEntry, 'visibility');
  Result.Enabled := TJsonRead.FlagOr(AEntry, 'enabled', True);
  Result.Checked := TJsonRead.FlagOr(AEntry, 'checked', False) and Result.Enabled;
  Result.Reason := StringOf(AEntry, 'reason');
  Result.CanAbstract := TJsonRead.FlagOr(AEntry, 'canAbstract', False) and Result.Enabled;
  Result.Abstract := TJsonRead.FlagOr(AEntry, 'abstract', False) and Result.CanAbstract;
  Result.Needs := IdsOf(AEntry, 'needs');
end;

function ReadMembers(APrepared: TJSONObject): TArray<TAtlasExtractionMember>;
var
  mEntry: TJSONObject;
begin
  Result := nil;
  for mEntry in ObjectsOf(APrepared, 'candidates') do
  begin
    Result := Result + [ReadMember(mEntry)];
  end;
end;

/// <summary>Stelle des Mitglieds mit der Kennung AId; -1 ohne.</summary>
function IndexIn(const AMembers: TArray<TAtlasExtractionMember>; AId: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(AMembers) downto 0 do
  begin
    if AMembers[mIndex].Id = AId then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Hakt an, was AMembers[AIndex] benutzt und noch fehlt; liefert die Zahl neu angehakter Einträge.
/// </summary>
function TakeNeedsOf(var AMembers: TArray<TAtlasExtractionMember>; AIndex: Integer): Integer;
var
  mNeed, mNeeded: Integer;
begin
  Result := 0;
  for mNeed in AMembers[AIndex].Needs do
  begin
    mNeeded := IndexIn(AMembers, mNeed);
    if (mNeeded >= 0) and AMembers[mNeeded].Enabled and not AMembers[mNeeded].Checked then
    begin
      AMembers[mNeeded].Checked := True;
      Inc(Result);
    end;
  end;
end;

{ TAtlasClassExtractionModel }

constructor TAtlasClassExtractionModel.Create(const APrepared: TJSONObject);
begin
  inherited Create;
  FSource := ReadSource(APrepared);
  FName := StringOf(APrepared, 'name');
  FTargetUnit := StringOf(APrepared, 'unit');
  FOption := TJsonRead.FlagOr(OptionOf(APrepared), 'value', False);
  FTargets := ReadTargets(APrepared);
  FMembers := ReadMembers(APrepared);
end;

function TAtlasClassExtractionModel.GetMember(AIndex: Integer): TAtlasExtractionMember;
begin
  Result := FMembers[AIndex];
end;

function TAtlasClassExtractionModel.GetCount: Integer;
begin
  Result := Length(FMembers);
end;

function TAtlasClassExtractionModel.GetTarget(AIndex: Integer): TAtlasExtractionTarget;
begin
  Result := FTargets[AIndex];
end;

function TAtlasClassExtractionModel.GetTargetCount: Integer;
begin
  Result := Length(FTargets);
end;

function TAtlasClassExtractionModel.IsMove: Boolean;
begin
  Result := FTargets <> nil;
end;

procedure TAtlasClassExtractionModel.SetTargetChecked(AIndex: Integer; AChecked: Boolean);
var
  mIndex: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FTargets)) then
  begin
    Exit;
  end;
  if not FSource.MultiTarget then
  begin
    // Ein Vorfahr: genau einer gewählt.
    for mIndex := 0 to High(FTargets) do
    begin
      FTargets[mIndex].Checked := mIndex = AIndex;
    end;
    Exit;
  end;
  FTargets[AIndex].Checked := AChecked;
end;

function TAtlasClassExtractionModel.CheckedTargets: TArray<string>;
var
  mItem: TAtlasExtractionTarget;
begin
  Result := nil;
  for mItem in FTargets do
  begin
    if mItem.Checked then
    begin
      Result := Result + [mItem.Name];
    end;
  end;
end;

function TAtlasClassExtractionModel.IndexOfId(AId: Integer): Integer;
begin
  Result := IndexIn(FMembers, AId);
end;

procedure TAtlasClassExtractionModel.SetChecked(AIndex: Integer; AChecked: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FMembers)) or not FMembers[AIndex].Enabled then
  begin
    Exit;
  end;
  FMembers[AIndex].Checked := AChecked;
end;

procedure TAtlasClassExtractionModel.CheckAll(AChecked: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FMembers) do
  begin
    SetChecked(mIndex, AChecked);
  end;
end;

function TAtlasClassExtractionModel.CheckedCount: Integer;
var
  mMember: TAtlasExtractionMember;
begin
  Result := 0;
  for mMember in FMembers do
  begin
    if mMember.Checked then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TAtlasClassExtractionModel.SetAbstract(AIndex: Integer; AAbstract: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FMembers)) or not FMembers[AIndex].CanAbstract then
  begin
    Exit;
  end;
  FMembers[AIndex].Abstract := AAbstract;
end;

function TAtlasClassExtractionModel.HasModes: Boolean;
var
  mMember: TAtlasExtractionMember;
begin
  Result := False;
  for mMember in FMembers do
  begin
    if mMember.CanAbstract then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasClassExtractionModel.HasNeeds: Boolean;
var
  mMember: TAtlasExtractionMember;
begin
  Result := False;
  for mMember in FMembers do
  begin
    if mMember.Needs <> nil then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasClassExtractionModel.MissingDependency(out AMember, ANeeded: string): Boolean;
var
  mMember: TAtlasExtractionMember;
  mNeed, mIndex: Integer;
begin
  AMember := '';
  ANeeded := '';
  // Eine abstrakte Methode nimmt ihren Rumpf nicht mit und braucht oben nichts.
  for mMember in FMembers do
  begin
    if mMember.Checked and not mMember.Abstract then
    begin
      for mNeed in mMember.Needs do
      begin
        mIndex := IndexOfId(mNeed);
        if (mIndex >= 0) and not FMembers[mIndex].Checked then
        begin
          AMember := mMember.Name;
          ANeeded := FMembers[mIndex].Name;
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

function TAtlasClassExtractionModel.TakeDependencies: Integer;
var
  mIndex, mTaken: Integer;
begin
  Result := 0;
  repeat
    mTaken := 0;
    for mIndex := 0 to High(FMembers) do
    begin
      if FMembers[mIndex].Checked and not FMembers[mIndex].Abstract then
      begin
        Inc(mTaken, TakeNeedsOf(FMembers, mIndex));
      end;
    end;
    Inc(Result, mTaken);
  until mTaken = 0;
end;

function TAtlasClassExtractionModel.Validate(out ASubject: string): TAtlasExtractionProblem;
var
  mCandidate, mMember, mNeeded: string;
begin
  Result := TAtlasExtractionProblem.None;
  mCandidate := Trim(FName);
  ASubject := mCandidate;
  if not IsMove and not IsName(mCandidate) then
  begin
    Result := TAtlasExtractionProblem.BadName;
  end
  else if not IsMove and SameText(mCandidate, FSource.SourceClass) then
  begin
    Result := TAtlasExtractionProblem.SameName;
  end
  else if CheckedCount = 0 then
  begin
    ASubject := '';
    Result := TAtlasExtractionProblem.NoMembers;
  end
  else if FSource.NeedsRequired and MissingDependency(mMember, mNeeded) then
  begin
    ASubject := mMember;
    Result := TAtlasExtractionProblem.MissingDependency;
  end
  else if IsMove then
  begin
    ASubject := '';
    if CheckedTargets = nil then
    begin
      Result := TAtlasExtractionProblem.NoTarget;
    end;
  end
  else
  begin
    mCandidate := Target;
    ASubject := '';
    if (mCandidate <> '') and not IsUnitName(mCandidate) then
    begin
      ASubject := mCandidate;
      Result := TAtlasExtractionProblem.BadUnit;
    end;
  end;
end;

function TAtlasClassExtractionModel.Validate: TAtlasExtractionProblem;
var
  mSubject: string;
begin
  Result := Validate(mSubject);
end;

function TAtlasClassExtractionModel.Target: string;
begin
  Result := Trim(FTargetUnit);
  if SameText(Result, FSource.OwnUnit) then
  begin
    Result := '';
  end;
end;

function TAtlasClassExtractionModel.RequestJson: TJSONObject;
var
  mList, mAbstracts: TJSONArray;
  mMember: TAtlasExtractionMember;
  mName: string;
begin
  Result := TJSONObject.Create;
  if not IsMove then
  begin
    Result.AddPair('name', Trim(FName));
    Result.AddPair('unit', Target);
  end;
  mList := TJSONArray.Create;
  for mMember in FMembers do
  begin
    if mMember.Checked then
    begin
      mList.AddElement(TJSONNumber.Create(mMember.Id));
    end;
  end;
  Result.AddPair('members', mList);
  mAbstracts := nil;
  for mMember in FMembers do
  begin
    if mMember.Checked and mMember.Abstract then
    begin
      if mAbstracts = nil then
      begin
        mAbstracts := TJSONArray.Create;
      end;
      mAbstracts.AddElement(TJSONNumber.Create(mMember.Id));
    end;
  end;
  if mAbstracts <> nil then
  begin
    Result.AddPair('abstract', mAbstracts);
  end;
  if not IsMove then
  begin
    Exit;
  end;
  mList := TJSONArray.Create;
  for mName in CheckedTargets do
  begin
    mList.Add(mName);
  end;
  Result.AddPair('targets', mList);
  if FSource.OptionKind <> '' then
  begin
    Result.AddPair('option', TJSONBool.Create(FOption));
  end;
end;

end.
