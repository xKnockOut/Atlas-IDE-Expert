unit Atlas.Core.Debug.StepInto;

// Gezielt hineinspringen (#836), Kern ohne IDE: liest die Antwort von
// atlas.server.stepTargets und baut daraus die Zeilen des Popups.
// - Je Aufruf eine Zeile: Nummer, Routine mit Klasse, Art (Getter, Setter,
//   Konstruktor, inherited), Datei:Zeile des Haltepunkts.
// - Virtuelle Methoden und Interface-Methoden: Der Laufzeittyp des Empfängers
//   entscheidet (Empfänger.ClassName, bei Interfaces (Empfänger as
//   TObject).ClassName, dann ClassParent für Klassen ohne eigene
//   Überschreibung). Ausgewertet wird nur, wenn der Empfänger selbst nichts
//   aufruft (receiverSimple). Geht das nicht, steht jede bekannte
//   Überschreibung als eigene Zeile da.
// - Nicht wählbar (ausgegraut): ohne Quelltext (kein Rumpf bekannt) und
//   Bibliothekscode, an dem kein Haltepunkt greift (RTL/VCL ohne Debug-DCUs);
//   das prüft der Aufrufer über ACanBreak.
// Die Auswertung und die Prüfung der Haltepunkte kommen als Rückrufe, damit
// alles ohne IDE testbar ist.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasStepKind = (Call, Constructor_, Getter, Setter, Inherited_);
  /// <summary>Warum eine Zeile nicht wählbar ist.</summary>
  TAtlasStepUnavailable = (None, NoSource, Library_);
  {$SCOPEDENUMS OFF}

  TAtlasStepTarget = record
    Container: string;
    Name: string;
    FileName: string;
    /// <summary>Zeile des begin (ab 0).</summary>
    Line: Integer;
  end;

  TAtlasStepCall = record
    Name: string;
    Container: string;
    Kind: TAtlasStepKind;
    Text: string;
    Receiver: string;
    ReceiverSimple: Boolean;
    ReceiverInterface: Boolean;
    IsVirtual: Boolean;
    DeclFile: string;
    DeclLine: Integer;
    Targets: TArray<TAtlasStepTarget>;
  end;

  TAtlasStepAnswer = record
    Line: Integer;
    FollowLine: Integer;
    Calls: TArray<TAtlasStepCall>;
  end;

  TAtlasStepRow = record
    /// <summary>Index in TAtlasStepAnswer.Calls.</summary>
    Call: Integer;
    /// <summary>TKunde.GetName bzw. Format.</summary>
    Caption: string;
    Kind: TAtlasStepKind;
    /// <summary>Kunden.pas:42 (Haltepunkt bzw. Deklaration); '' ohne.</summary>
    Location: string;
    HasTarget: Boolean;
    Target: TAtlasStepTarget;
    Unavailable: TAtlasStepUnavailable;
    /// <summary>Eine von mehreren Überschreibungen, weil der Laufzeittyp unbekannt blieb.</summary>
    Candidate: Boolean;
    function Available: Boolean;
  end;

  /// <summary>Wertet AExpression im angehaltenen Programm aus; False, wenn das nicht geht.</summary>
  TAtlasStepEvaluate = reference to function(const AExpression: string; out AValue: string): Boolean;
  /// <summary>Greift ein Haltepunkt in AFileName (eigener Code oder Bibliothek mit Debug-DCUs)?</summary>
  TAtlasStepCanBreak = reference to function(const AFileName: string): Boolean;

  TAtlasStepInto = class
  public const
    Command = 'atlas.server.stepTargets';
    /// <summary>Höchstens so viele Stufen ClassParent beim Suchen der Überschreibung.</summary>
    MaxAncestors = 16;
    /// <summary>Mit 1–9 direkt wählbar.</summary>
    MaxDigit = 9;
  private
    class function KindOf(const AText: string): TAtlasStepKind; static;
    class function RowOf(const AAnswer: TAtlasStepAnswer; ACall: Integer; const ATarget: TAtlasStepTarget;
      AHasTarget: Boolean; const ACanBreak: TAtlasStepCanBreak): TAtlasStepRow; static;
  public
    /// <summary>JSON-Argumente [uri, line] für den Befehl.</summary>
    class function Arguments(const AUri: string; ALine: Integer): string; static;
    /// <summary>Antwort lesen; False bei fremdem Format.</summary>
    class function ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasStepAnswer): Boolean; static;
    /// <summary>Ausdruck für den Klassennamen des Empfängers (Kunde.ClassName, (D as TObject).ClassName) mit
    /// ADepth-mal ClassParent; '' wenn der Empfänger nicht ohne Aufrufe auswertbar ist.</summary>
    class function ClassExpression(const ACall: TAtlasStepCall; ADepth: Integer): string; static;
    /// <summary>Überschreibung für den Laufzeittyp; False, wenn er nicht ermittelbar ist oder keine passt.</summary>
    class function PickTarget(const ACall: TAtlasStepCall; const AEvaluate: TAtlasStepEvaluate;
      out ATarget: TAtlasStepTarget): Boolean; static;
    /// <summary>Zeilen des Popups in Ausführungsreihenfolge.</summary>
    class function Rows(const AAnswer: TAtlasStepAnswer; const AEvaluate: TAtlasStepEvaluate;
      const ACanBreak: TAtlasStepCanBreak): TArray<TAtlasStepRow>; static;
    /// <summary>Nächste wählbare Zeile ab AFrom in Richtung ADelta (±1); -1 ohne.</summary>
    class function NextAvailable(const ARows: TArray<TAtlasStepRow>; AFrom, ADelta: Integer): Integer; static;
    /// <summary>Zeile zur Ziffer ADigit (1–9), wenn sie wählbar ist; sonst -1.</summary>
    class function DigitRow(const ARows: TArray<TAtlasStepRow>; ADigit: Integer): Integer; static;
    /// <summary>Höchstens ein Aufruf: Der Befehl wirkt wie F7.</summary>
    class function ActsLikeStepInto(const ARows: TArray<TAtlasStepRow>): Boolean; static;
    /// <summary>Liegt AFileName unter dem Quelltext von RAD Studio (ARoot\source)?</summary>
    class function IsLibraryFile(const AFileName, ARoot: string): Boolean; static;
    /// <summary>'TKunde' bzw. TKunde aus der Auswertung ohne Hochkommas.</summary>
    class function Unquote(const AValue: string): string; static;
    /// <summary>Letzter Namensteil eines Typs (TAussen.TInnen → TInnen, Unit.TKunde → TKunde).</summary>
    class function ShortName(const ATypeName: string): string; static;
  end;

implementation

uses
  System.StrUtils;

{ TAtlasStepRow }

function TAtlasStepRow.Available: Boolean;
begin
  Result := HasTarget and (Unavailable = TAtlasStepUnavailable.None);
end;

{ TAtlasStepInto }

class function TAtlasStepInto.Arguments(const AUri: string; ALine: Integer): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Items.Add(ALine);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasStepInto.KindOf(const AText: string): TAtlasStepKind;
begin
  if AText = 'constructor' then
    Result := TAtlasStepKind.Constructor_
  else if AText = 'getter' then
    Result := TAtlasStepKind.Getter
  else if AText = 'setter' then
    Result := TAtlasStepKind.Setter
  else if AText = 'inherited' then
    Result := TAtlasStepKind.Inherited_
  else
    Result := TAtlasStepKind.Call;
end;

class function TAtlasStepInto.ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasStepAnswer): Boolean;
var
  Root, Item, TargetItem: TJSONObject;
  Calls, Targets: TJSONArray;
  Index, TargetIndex: Integer;
  Call: TAtlasStepCall;
  Target: TAtlasStepTarget;
begin
  AAnswer := Default(TAtlasStepAnswer);
  AAnswer.FollowLine := -1;
  Result := False;
  if not (AJson is TJSONObject) then
    Exit;
  Root := TJSONObject(AJson);
  if Root.GetValue<Integer>('format', 0) <> 1 then
    Exit;
  AAnswer.Line := Root.GetValue<Integer>('line', -1);
  AAnswer.FollowLine := Root.GetValue<Integer>('followLine', -1);
  if not Root.TryGetValue<TJSONArray>('calls', Calls) then
    Exit(True);
  for Index := 0 to Calls.Count - 1 do
  begin
    if not (Calls.Items[Index] is TJSONObject) then
      Continue;
    Item := TJSONObject(Calls.Items[Index]);
    Call := Default(TAtlasStepCall);
    Call.Name := Item.GetValue<string>('name', '');
    Call.Container := Item.GetValue<string>('container', '');
    Call.Kind := KindOf(Item.GetValue<string>('kind', ''));
    Call.Text := Item.GetValue<string>('text', '');
    Call.Receiver := Item.GetValue<string>('receiver', '');
    Call.ReceiverSimple := Item.GetValue<Boolean>('receiverSimple', False);
    Call.ReceiverInterface := Item.GetValue<Boolean>('receiverInterface', False);
    Call.IsVirtual := Item.GetValue<Boolean>('virtual', False);
    Call.DeclFile := Item.GetValue<string>('declFile', '');
    Call.DeclLine := Item.GetValue<Integer>('declLine', -1);
    if Item.TryGetValue<TJSONArray>('targets', Targets) then
      for TargetIndex := 0 to Targets.Count - 1 do
        if Targets.Items[TargetIndex] is TJSONObject then
        begin
          TargetItem := TJSONObject(Targets.Items[TargetIndex]);
          Target.Container := TargetItem.GetValue<string>('container', '');
          Target.Name := TargetItem.GetValue<string>('name', '');
          Target.FileName := TargetItem.GetValue<string>('file', '');
          Target.Line := TargetItem.GetValue<Integer>('line', -1);
          if (Target.FileName <> '') and (Target.Line >= 0) then
            Call.Targets := Call.Targets + [Target];
        end;
    if Call.Name <> '' then
      AAnswer.Calls := AAnswer.Calls + [Call];
  end;
  Result := True;
end;

class function TAtlasStepInto.ShortName(const ATypeName: string): string;
var
  Angle, Dot: Integer;
begin
  Result := Trim(ATypeName);
  Angle := Pos('<', Result);
  if Angle > 0 then
    Result := Copy(Result, 1, Angle - 1);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

class function TAtlasStepInto.Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

class function TAtlasStepInto.ClassExpression(const ACall: TAtlasStepCall; ADepth: Integer): string;
var
  Level: Integer;
begin
  Result := '';
  if (ACall.Receiver = '') or not ACall.ReceiverSimple then
    Exit;
  if ACall.ReceiverInterface then
    Result := '(' + ACall.Receiver + ' as TObject)'
  else
    Result := ACall.Receiver;
  for Level := 1 to ADepth do
    Result := Result + '.ClassParent';
  Result := Result + '.ClassName';
end;

class function TAtlasStepInto.PickTarget(const ACall: TAtlasStepCall; const AEvaluate: TAtlasStepEvaluate;
  out ATarget: TAtlasStepTarget): Boolean;
var
  Depth: Integer;
  Expression, Value, Name: string;
  Target: TAtlasStepTarget;
begin
  Result := False;
  if not Assigned(AEvaluate) then
    Exit;
  for Depth := 0 to MaxAncestors do
  begin
    Expression := ClassExpression(ACall, Depth);
    if (Expression = '') or not AEvaluate(Expression, Value) then
      Exit;
    Name := Unquote(Value);
    if Name = '' then
      Exit;
    // Die nächste Klasse mit eigenem Rumpf gewinnt.
    for Target in ACall.Targets do
      if SameText(ShortName(Target.Container), ShortName(Name)) then
      begin
        ATarget := Target;
        Exit(True);
      end;
    if SameText(Name, 'TObject') then
      Exit;
  end;
end;

class function TAtlasStepInto.RowOf(const AAnswer: TAtlasStepAnswer; ACall: Integer;
  const ATarget: TAtlasStepTarget; AHasTarget: Boolean; const ACanBreak: TAtlasStepCanBreak): TAtlasStepRow;
var
  Call: TAtlasStepCall;
begin
  Call := AAnswer.Calls[ACall];
  Result := Default(TAtlasStepRow);
  Result.Call := ACall;
  Result.Kind := Call.Kind;
  Result.HasTarget := AHasTarget;
  Result.Target := ATarget;
  if AHasTarget then
  begin
    if ATarget.Container <> '' then
      Result.Caption := ATarget.Container + '.' + ATarget.Name
    else
      Result.Caption := ATarget.Name;
    Result.Location := ExtractFileName(ATarget.FileName) + ':' + IntToStr(ATarget.Line + 1);
    if Assigned(ACanBreak) and not ACanBreak(ATarget.FileName) then
      Result.Unavailable := TAtlasStepUnavailable.Library_;
  end
  else
  begin
    if Call.Container <> '' then
      Result.Caption := Call.Container + '.' + Call.Name
    else
      Result.Caption := Call.Name;
    if (Call.DeclFile <> '') and (Call.DeclLine >= 0) then
      Result.Location := ExtractFileName(Call.DeclFile) + ':' + IntToStr(Call.DeclLine + 1);
    Result.Unavailable := TAtlasStepUnavailable.NoSource;
  end;
end;

class function TAtlasStepInto.Rows(const AAnswer: TAtlasStepAnswer; const AEvaluate: TAtlasStepEvaluate;
  const ACanBreak: TAtlasStepCanBreak): TArray<TAtlasStepRow>;
var
  Index: Integer;
  Call: TAtlasStepCall;
  Target: TAtlasStepTarget;
  Row: TAtlasStepRow;
begin
  Result := nil;
  for Index := 0 to High(AAnswer.Calls) do
  begin
    Call := AAnswer.Calls[Index];
    if Length(Call.Targets) = 0 then
      Result := Result + [RowOf(AAnswer, Index, Default(TAtlasStepTarget), False, ACanBreak)]
    else if not Call.IsVirtual or (Length(Call.Targets) = 1) then
      Result := Result + [RowOf(AAnswer, Index, Call.Targets[0], True, ACanBreak)]
    else if PickTarget(Call, AEvaluate, Target) then
      Result := Result + [RowOf(AAnswer, Index, Target, True, ACanBreak)]
    else
      // Laufzeittyp unbekannt: jede Überschreibung zur Wahl.
      for Target in Call.Targets do
      begin
        Row := RowOf(AAnswer, Index, Target, True, ACanBreak);
        Row.Candidate := True;
        Result := Result + [Row];
      end;
  end;
end;

class function TAtlasStepInto.NextAvailable(const ARows: TArray<TAtlasStepRow>; AFrom, ADelta: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  if ADelta = 0 then
    Exit;
  Index := AFrom;
  while (Index >= 0) and (Index <= High(ARows)) do
  begin
    if ARows[Index].Available then
      Exit(Index);
    Inc(Index, ADelta);
  end;
end;

class function TAtlasStepInto.DigitRow(const ARows: TArray<TAtlasStepRow>; ADigit: Integer): Integer;
begin
  Result := -1;
  if (ADigit >= 1) and (ADigit <= MaxDigit) and (ADigit <= Length(ARows)) and ARows[ADigit - 1].Available then
    Result := ADigit - 1;
end;

class function TAtlasStepInto.ActsLikeStepInto(const ARows: TArray<TAtlasStepRow>): Boolean;
begin
  Result := Length(ARows) <= 1;
end;

class function TAtlasStepInto.IsLibraryFile(const AFileName, ARoot: string): Boolean;
var
  Source: string;
begin
  Result := False;
  if (AFileName = '') or (ARoot = '') then
    Exit;
  // Beide Trenner gelten, die IDE meldet Pfade nicht immer gleich.
  Source := ARoot.Replace('/', '\');
  if not EndsText('\', Source) then
    Source := Source + '\';
  Result := StartsText(Source + 'source\', AFileName.Replace('/', '\'));
end;

end.
