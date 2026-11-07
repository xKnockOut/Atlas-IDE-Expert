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
  System.Generics.Collections,
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
    cCommand = 'atlas.server.stepTargets';
    /// <summary>Höchstens so viele Stufen ClassParent beim Suchen der Überschreibung.</summary>
    cMaxAncestors = 16;
    /// <summary>Mit 1–9 direkt wählbar.</summary>
    cMaxDigit = 9;
  private
    class function KindOf(const AText: string): TAtlasStepKind; static;
    /// <summary>Ziele eines Aufrufs aus "targets"; ohne Datei oder Zeile fällt ein Eintrag weg.</summary>
    class function ReadTargets(AItem: TJSONObject): TArray<TAtlasStepTarget>; static;
    /// <summary>Ein Aufruf aus einem Eintrag von "calls".</summary>
    class function ReadCall(AItem: TJSONObject): TAtlasStepCall; static;
    /// <summary>Das Ziel aus ACall.Targets, dessen Klasse AName heißt.</summary>
    class function MatchTarget(const ACall: TAtlasStepCall; const AName: string;
      out ATarget: TAtlasStepTarget): Boolean; static;
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
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(ALine);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasStepInto.KindOf(const AText: string): TAtlasStepKind;
begin
  if AText = 'constructor' then
  begin
    Result := TAtlasStepKind.Constructor_;
  end
  else if AText = 'getter' then
  begin
    Result := TAtlasStepKind.Getter;
  end
  else if AText = 'setter' then
  begin
    Result := TAtlasStepKind.Setter;
  end
  else if AText = 'inherited' then
  begin
    Result := TAtlasStepKind.Inherited_;
  end
  else
  begin
    Result := TAtlasStepKind.Call;
  end;
end;

class function TAtlasStepInto.ReadTargets(AItem: TJSONObject): TArray<TAtlasStepTarget>;
var
  mTargets: TJSONArray;
  mTargetItem: TJSONObject;
  mIndex: Integer;
  mTarget: TAtlasStepTarget;
begin
  Result := nil;
  if not AItem.TryGetValue<TJSONArray>('targets', mTargets) then
  begin
    Exit;
  end;
  for mIndex := 0 to mTargets.Count - 1 do
  begin
    if mTargets.Items[mIndex] is TJSONObject then
    begin
      mTargetItem := TJSONObject(mTargets.Items[mIndex]);
      mTarget.Container := mTargetItem.GetValue<string>('container', '');
      mTarget.Name := mTargetItem.GetValue<string>('name', '');
      mTarget.FileName := mTargetItem.GetValue<string>('file', '');
      mTarget.Line := mTargetItem.GetValue<Integer>('line', -1);
      if (mTarget.FileName <> '') and (mTarget.Line >= 0) then
      begin
        Result := Result + [mTarget];
      end;
    end;
  end;
end;

class function TAtlasStepInto.ReadCall(AItem: TJSONObject): TAtlasStepCall;
begin
  Result := Default(TAtlasStepCall);
  Result.Name := AItem.GetValue<string>('name', '');
  Result.Container := AItem.GetValue<string>('container', '');
  Result.Kind := KindOf(AItem.GetValue<string>('kind', ''));
  Result.Text := AItem.GetValue<string>('text', '');
  Result.Receiver := AItem.GetValue<string>('receiver', '');
  Result.ReceiverSimple := AItem.GetValue<Boolean>('receiverSimple', False);
  Result.ReceiverInterface := AItem.GetValue<Boolean>('receiverInterface', False);
  Result.IsVirtual := AItem.GetValue<Boolean>('virtual', False);
  Result.DeclFile := AItem.GetValue<string>('declFile', '');
  Result.DeclLine := AItem.GetValue<Integer>('declLine', -1);
  Result.Targets := ReadTargets(AItem);
end;

class function TAtlasStepInto.ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasStepAnswer): Boolean;
var
  mRoot: TJSONObject;
  mCalls: TJSONArray;
  mIndex: Integer;
  mCall: TAtlasStepCall;
begin
  AAnswer := Default(TAtlasStepAnswer);
  AAnswer.FollowLine := -1;
  Result := False;
  if not (AJson is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AJson);
  if mRoot.GetValue<Integer>('format', 0) <> 1 then
  begin
    Exit;
  end;
  AAnswer.Line := mRoot.GetValue<Integer>('line', -1);
  AAnswer.FollowLine := mRoot.GetValue<Integer>('followLine', -1);
  if not mRoot.TryGetValue<TJSONArray>('calls', mCalls) then
  begin
    Exit(True);
  end;
  for mIndex := 0 to mCalls.Count - 1 do
  begin
    if not (mCalls.Items[mIndex] is TJSONObject) then
    begin
      Continue;
    end;
    mCall := ReadCall(TJSONObject(mCalls.Items[mIndex]));
    if mCall.Name <> '' then
    begin
      AAnswer.Calls := AAnswer.Calls + [mCall];
    end;
  end;
  Result := True;
end;

class function TAtlasStepInto.ShortName(const ATypeName: string): string;
var
  mAngle, mDot: Integer;
begin
  Result := Trim(ATypeName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Copy(Result, 1, mAngle - 1);
  end;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TAtlasStepInto.Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

class function TAtlasStepInto.ClassExpression(const ACall: TAtlasStepCall; ADepth: Integer): string;
var
  mLevel: Integer;
begin
  Result := '';
  if (ACall.Receiver = '') or not ACall.ReceiverSimple then
  begin
    Exit;
  end;
  if ACall.ReceiverInterface then
  begin
    Result := '(' + ACall.Receiver + ' as TObject)';
  end
  else
  begin
    Result := ACall.Receiver;
  end;
  for mLevel := 1 to ADepth do
  begin
    Result := Result + '.ClassParent';
  end;
  Result := Result + '.ClassName';
end;

class function TAtlasStepInto.MatchTarget(const ACall: TAtlasStepCall; const AName: string;
  out ATarget: TAtlasStepTarget): Boolean;
var
  mTarget: TAtlasStepTarget;
begin
  Result := False;
  for mTarget in ACall.Targets do
  begin
    if SameText(ShortName(mTarget.Container), ShortName(AName)) then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
end;

class function TAtlasStepInto.PickTarget(const ACall: TAtlasStepCall; const AEvaluate: TAtlasStepEvaluate;
  out ATarget: TAtlasStepTarget): Boolean;
var
  mDepth: Integer;
  mExpression, mValue, mName: string;
  mDone: Boolean;
begin
  Result := False;
  if not Assigned(AEvaluate) then
  begin
    Exit;
  end;
  mDepth := 0;
  mDone := False;
  while not mDone and (mDepth <= cMaxAncestors) do
  begin
    mExpression := ClassExpression(ACall, mDepth);
    mName := '';
    if (mExpression <> '') and AEvaluate(mExpression, mValue) then
    begin
      mName := Unquote(mValue);
    end;
    // Die nächste Klasse mit eigenem Rumpf gewinnt; ohne Namen oder bei TObject endet die Suche.
    Result := (mName <> '') and MatchTarget(ACall, mName, ATarget);
    mDone := Result or (mName = '') or SameText(mName, 'TObject');
    Inc(mDepth);
  end;
end;

class function TAtlasStepInto.RowOf(const AAnswer: TAtlasStepAnswer; ACall: Integer;
  const ATarget: TAtlasStepTarget; AHasTarget: Boolean; const ACanBreak: TAtlasStepCanBreak): TAtlasStepRow;
var
  mCall: TAtlasStepCall;
begin
  mCall := AAnswer.Calls[ACall];
  Result := Default(TAtlasStepRow);
  Result.Call := ACall;
  Result.Kind := mCall.Kind;
  Result.HasTarget := AHasTarget;
  Result.Target := ATarget;
  if AHasTarget then
  begin
    if ATarget.Container <> '' then
    begin
      Result.Caption := ATarget.Container + '.' + ATarget.Name;
    end
    else
    begin
      Result.Caption := ATarget.Name;
    end;
    Result.Location := ExtractFileName(ATarget.FileName) + ':' + IntToStr(ATarget.Line + 1);
    if Assigned(ACanBreak) and not ACanBreak(ATarget.FileName) then
    begin
      Result.Unavailable := TAtlasStepUnavailable.Library_;
    end;
  end
  else
  begin
    if mCall.Container <> '' then
    begin
      Result.Caption := mCall.Container + '.' + mCall.Name;
    end
    else
    begin
      Result.Caption := mCall.Name;
    end;
    if (mCall.DeclFile <> '') and (mCall.DeclLine >= 0) then
    begin
      Result.Location := ExtractFileName(mCall.DeclFile) + ':' + IntToStr(mCall.DeclLine + 1);
    end;
    Result.Unavailable := TAtlasStepUnavailable.NoSource;
  end;
end;

class function TAtlasStepInto.Rows(const AAnswer: TAtlasStepAnswer; const AEvaluate: TAtlasStepEvaluate;
  const ACanBreak: TAtlasStepCanBreak): TArray<TAtlasStepRow>;
var
  mIndex: Integer;
  mCall: TAtlasStepCall;
  mTarget: TAtlasStepTarget;
  mRow: TAtlasStepRow;
begin
  Result := nil;
  for mIndex := 0 to High(AAnswer.Calls) do
  begin
    mCall := AAnswer.Calls[mIndex];
    if Length(mCall.Targets) = 0 then
    begin
      Result := Result + [RowOf(AAnswer, mIndex, Default(TAtlasStepTarget), False, ACanBreak)];
    end
    else if not mCall.IsVirtual or (Length(mCall.Targets) = 1) then
    begin
      Result := Result + [RowOf(AAnswer, mIndex, mCall.Targets[0], True, ACanBreak)];
    end
    else if PickTarget(mCall, AEvaluate, mTarget) then
    begin
      Result := Result + [RowOf(AAnswer, mIndex, mTarget, True, ACanBreak)];
    end
    else
    begin
      // Laufzeittyp unbekannt: jede Überschreibung zur Wahl.
      for mTarget in mCall.Targets do
      begin
        mRow := RowOf(AAnswer, mIndex, mTarget, True, ACanBreak);
        mRow.Candidate := True;
        Result := Result + [mRow];
      end;
    end;
  end;
end;

class function TAtlasStepInto.NextAvailable(const ARows: TArray<TAtlasStepRow>; AFrom, ADelta: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if ADelta = 0 then
  begin
    Exit;
  end;
  mIndex := AFrom;
  while (mIndex >= 0) and (mIndex <= High(ARows)) do
  begin
    if ARows[mIndex].Available then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex, ADelta);
  end;
end;

class function TAtlasStepInto.DigitRow(const ARows: TArray<TAtlasStepRow>; ADigit: Integer): Integer;
begin
  Result := -1;
  if (ADigit >= 1) and (ADigit <= cMaxDigit) and (ADigit <= Length(ARows)) and ARows[ADigit - 1].Available then
  begin
    Result := ADigit - 1;
  end;
end;

class function TAtlasStepInto.ActsLikeStepInto(const ARows: TArray<TAtlasStepRow>): Boolean;
begin
  Result := Length(ARows) <= 1;
end;

class function TAtlasStepInto.IsLibraryFile(const AFileName, ARoot: string): Boolean;
var
  mSource: string;
begin
  Result := False;
  if (AFileName = '') or (ARoot = '') then
  begin
    Exit;
  end;
  // Beide Trenner gelten, die IDE meldet Pfade nicht immer gleich.
  mSource := ARoot.Replace('/', '\');
  if not EndsText('\', mSource) then
  begin
    mSource := mSource + '\';
  end;
  Result := StartsText(mSource + 'source\', AFileName.Replace('/', '\'));
end;

end.
