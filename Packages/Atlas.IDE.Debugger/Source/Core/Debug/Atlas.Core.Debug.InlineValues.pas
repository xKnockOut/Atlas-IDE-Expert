unit Atlas.Core.Debug.InlineValues;

// Werte im Editor beim Debuggen (#508), ohne VCL und Open Tools API:
//   - Start: Bezeichner aus textDocument/inlineValue des Servers (lokale
//     Variablen, Parameter, Schleifenvariablen, Felder von Self) je Zeile,
//     jeder Name einmal je Zeile, höchstens debug.inlineValuesPerLine.
//     Nur schlichte Bezeichner kommen in die Auswertung (kein Punkt, keine
//     Klammer, kein reserviertes Wort): Ein Aufruf ist so ausgeschlossen,
//     auch wenn der Server sich irrt.
//   - Reihenfolge der Auswertung: die Zeile des Halts zuerst, dann die Zeilen
//     darüber, die nächste zuerst; jeder Name nur einmal.
//   - Put: Wert des Debuggers lesbar machen (TDateTime, TDate, TTime als Datum
//     bzw. Uhrzeit), lange Werte kürzen. Mengen, Aufzählungen und nil zeigt
//     der Debugger der IDE schon lesbar an.
//   - Geändert: Wert anders als beim letzten Halt in derselben Routine.
//     Clear (Fortsetzen) und Start merken die fertigen Werte dafür.
//   - Kein Zugriff (#840): Ein Fehlertext, den TAtlasDebugUnavailable als
//     „kein Zugriff“ erkennt, erscheint mit SetUnavailable als
//     „Name = ‹kein Zugriff›“; andere Fehler und ohne SetUnavailable fehlt
//     der Name wie bisher. Die Ursache nennt der Hover über dem Namen.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Lsp.Contract;

type
  {$SCOPEDENUMS ON}
  TAtlasInlineValueState = (Pending, Ready, Failed, Unavailable);
  {$SCOPEDENUMS OFF}

  TAtlasInlineValueItem = record
    Name: string;
    /// <summary>Darstellung (lesbar, gekürzt); '' solange Pending.</summary>
    Text: string;
    State: TAtlasInlineValueState;
    /// <summary>Anders als beim letzten Halt in derselben Routine.</summary>
    Changed: Boolean;
    /// <summary>„Name = Wert“.</summary>
    function Caption: string;
  end;

  TAtlasInlineValueItems = TArray<TAtlasInlineValueItem>;

  TAtlasInlineValues = class
  public const
    /// <summary>Längere Werte werden gekürzt.</summary>
    cMaxValueLength = 40;
  private type
    TValue = record
      Raw: string;
      Text: string;
      State: TAtlasInlineValueState;
    end;
  private
    FFileName: string;
    FContext: string;
    FStoppedLine: Integer;
    FLines: TDictionary<Integer, TArray<string>>;
    FOrder: TList<string>;
    FTypes: TDictionary<string, string>;
    /// <summary>Schreibweise der ersten Stelle je Name für die Anzeige.</summary>
    FSpellings: TDictionary<string, string>;
    FValues: TDictionary<string, TValue>;
    FPrevious: TDictionary<string, string>;
    FPreviousContext: string;
    FNext: Integer;
    FUnavailableText: string;
    FUnavailablePatterns: TArray<string>;
    /// <summary>Fertige Werte für die Hervorhebung beim nächsten Halt merken.</summary>
    procedure Remember;
    /// <summary>Höchstens APerLine verschiedene Namen je Zeile übernehmen.</summary>
    procedure AddRefs(const ARefs: TAtlasInlineValueRefs; APerLine: Integer);
    class function KeyOf(const AName: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Halt in AFileName an AStoppedLine (0-basiert); AContext unterscheidet Routinen (Datei und
    /// Routine), nur dort zählen Änderungen. APerLine: höchstens so viele Werte je Zeile.</summary>
    procedure Start(const AFileName, AContext: string; AStoppedLine: Integer; const ARefs: TAtlasInlineValueRefs;
      APerLine: Integer);
    /// <summary>Halt vorbei: Werte vergessen; die fertigen bleiben für die Hervorhebung gemerkt.</summary>
    procedure Clear;
    /// <summary>Alles vergessen, auch die gemerkten Werte (Ende der Sitzung).</summary>
    procedure Reset;
    /// <summary>Nächster Name ohne Wert in der Reihenfolge der Auswertung; False, wenn alle da sind.</summary>
    function NextPending(out AName: string): Boolean;
    /// <summary>„Kein Zugriff“ zeigen (#840): AText statt des Werts, wenn der Fehlertext als solcher erkannt
    /// wird (bekannte Texte und APatterns); AText = '' blendet solche Namen wie andere Fehler aus.</summary>
    procedure SetUnavailable(const AText: string; const APatterns: TArray<string>);
    /// <summary>Wert für AName; AOk = False: der Debugger kennt ihn nicht (wird nicht angezeigt, außer bei
    /// „kein Zugriff“ mit SetUnavailable).</summary>
    procedure Put(const AName, ARaw: string; AOk: Boolean);
    /// <summary>Werte der Zeile ALine (0-basiert) in AFileName, in der Reihenfolge im Text; nur fertige und
    /// „kein Zugriff“.</summary>
    function Line(const AFileName: string; ALine: Integer): TAtlasInlineValueItems;
    /// <summary>Gibt es Bezeichner für den Halt?</summary>
    function Active: Boolean;
    property FileName: string read FFileName;
    property StoppedLine: Integer read FStoppedLine;
    /// <summary>Darf AName ausgewertet werden? Nur schlichte Bezeichner, keine reservierten Wörter.</summary>
    class function IsPlainIdentifier(const AName: string): Boolean; static;
    /// <summary>Lesbare, gekürzte Darstellung von ARaw für den Typ ATypeName.</summary>
    class function Display(const ATypeName, ARaw: string): string; static;
    /// <summary>„Count = 3, Name = 'Meier'“.</summary>
    class function LineText(const AItems: TAtlasInlineValueItems): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Unavailable;

const
  // Gültige Tage von TDateTime (0001-01-01 bis 9999-12-31).
  cMinDateTime = -693593.0;
  cMaxDateTime = 2958466.0;

{ TAtlasInlineValueItem }

function TAtlasInlineValueItem.Caption: string;
begin
  Result := Name + ' = ' + Text;
end;

{ TAtlasInlineValues }

constructor TAtlasInlineValues.Create;
begin
  inherited Create;
  FLines := TDictionary<Integer, TArray<string>>.Create;
  FOrder := TList<string>.Create;
  FTypes := TDictionary<string, string>.Create;
  FSpellings := TDictionary<string, string>.Create;
  FValues := TDictionary<string, TValue>.Create;
  FPrevious := TDictionary<string, string>.Create;
  FStoppedLine := -1;
end;

destructor TAtlasInlineValues.Destroy;
begin
  FPrevious.Free;
  FValues.Free;
  FSpellings.Free;
  FTypes.Free;
  FOrder.Free;
  FLines.Free;
  inherited Destroy;
end;

class function TAtlasInlineValues.KeyOf(const AName: string): string;
begin
  Result := LowerCase(AName);
end;

class function TAtlasInlineValues.IsPlainIdentifier(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if (AName = '') or CharInSet(AName[1], ['0'..'9']) or TAtlasDebugExpression.IsReserved(AName) then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(AName) do
  begin
    if not (CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AName[mIndex]) > 127)) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

procedure TAtlasInlineValues.Remember;
var
  mPair: TPair<string, TValue>;
begin
  if FValues.Count = 0 then
  begin
    Exit;
  end;
  if FPreviousContext <> FContext then
  begin
    FPrevious.Clear;
  end;
  FPreviousContext := FContext;
  for mPair in FValues do
  begin
    if mPair.Value.State = TAtlasInlineValueState.Ready then
    begin
      FPrevious.AddOrSetValue(mPair.Key, mPair.Value.Raw);
    end;
  end;
end;

/// <summary>Bezüge mit einfachem Namen in der Reihenfolge im Text; der Server liefert sie schon so, aber darauf
/// verlässt sich die Anzeige nicht.</summary>
function SortedRefs(const ARefs: TAtlasInlineValueRefs): TArray<TAtlasInlineValueRef>;
var
  mRef: TAtlasInlineValueRef;
  mSorted: TList<TAtlasInlineValueRef>;
begin
  mSorted := TList<TAtlasInlineValueRef>.Create;
  try
    for mRef in ARefs do
    begin
      if TAtlasInlineValues.IsPlainIdentifier(mRef.Name) then
      begin
        mSorted.Add(mRef);
      end;
    end;
    mSorted.Sort(TDelegatedComparer<TAtlasInlineValueRef>.Construct(
      function(const ALeft, ARight: TAtlasInlineValueRef): Integer
      begin
        Result := ALeft.Line - ARight.Line;
        if Result = 0 then
        begin
          Result := ALeft.Character - ARight.Character;
        end;
      end));
    Result := mSorted.ToArray;
  finally
    mSorted.Free;
  end;
end;

/// <summary>Zeilen nach Abstand zu AStoppedLine, bei gleichem Abstand die untere zuerst.</summary>
function LinesByDistance(const ALines: TArray<Integer>; AStoppedLine: Integer): TArray<Integer>;
begin
  Result := Copy(ALines);
  TArray.Sort<Integer>(Result, TDelegatedComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := Abs(ALeft - AStoppedLine) - Abs(ARight - AStoppedLine);
      if Result = 0 then
      begin
        Result := ARight - ALeft;
      end;
    end));
end;

procedure TAtlasInlineValues.AddRefs(const ARefs: TAtlasInlineValueRefs; APerLine: Integer);
var
  mRef: TAtlasInlineValueRef;
  mNames: TArray<string>;
  mKey: string;
begin
  for mRef in SortedRefs(ARefs) do
  begin
    mKey := KeyOf(mRef.Name);
    if not FLines.TryGetValue(mRef.Line, mNames) then
    begin
      mNames := nil;
    end;
    if (Length(mNames) >= APerLine) or (IndexStr(mKey, mNames) >= 0) then
    begin
      Continue;
    end;
    FLines.AddOrSetValue(mRef.Line, mNames + [mKey]);
    if not FTypes.ContainsKey(mKey) then
    begin
      FTypes.Add(mKey, mRef.TypeName);
      FSpellings.Add(mKey, mRef.Name);
      FValues.Add(mKey, Default(TValue));
    end;
  end;
end;

procedure TAtlasInlineValues.Start(const AFileName, AContext: string; AStoppedLine: Integer;
  const ARefs: TAtlasInlineValueRefs; APerLine: Integer);
var
  mKey: string;
  mLine: Integer;
begin
  Clear;
  if not SameText(FPreviousContext, AContext) then
  begin
    FPrevious.Clear;
    FPreviousContext := AContext;
  end;
  FFileName := AFileName;
  FContext := AContext;
  FStoppedLine := AStoppedLine;
  AddRefs(ARefs, Max(APerLine, 1));
  // Auswerten: Zeile des Halts zuerst, dann darüber die nächste zuerst.
  for mLine in LinesByDistance(FLines.Keys.ToArray, AStoppedLine) do
  begin
    for mKey in FLines[mLine] do
    begin
      if not FOrder.Contains(mKey) then
      begin
        FOrder.Add(mKey);
      end;
    end;
  end;
end;

procedure TAtlasInlineValues.Clear;
begin
  Remember;
  FLines.Clear;
  FOrder.Clear;
  FTypes.Clear;
  FSpellings.Clear;
  FValues.Clear;
  FNext := 0;
  FFileName := '';
  FStoppedLine := -1;
end;

procedure TAtlasInlineValues.Reset;
begin
  Clear;
  FPrevious.Clear;
  FPreviousContext := '';
  FContext := '';
end;

function TAtlasInlineValues.Active: Boolean;
begin
  Result := FOrder.Count > 0;
end;

function TAtlasInlineValues.NextPending(out AName: string): Boolean;
var
  mKey: string;
begin
  AName := '';
  while FNext < FOrder.Count do
  begin
    mKey := FOrder[FNext];
    if FValues[mKey].State = TAtlasInlineValueState.Pending then
    begin
      AName := FSpellings[mKey];
      Exit(True);
    end;
    Inc(FNext);
  end;
  Result := False;
end;

procedure TAtlasInlineValues.Put(const AName, ARaw: string; AOk: Boolean);
var
  mKey: string;
  mValue: TValue;
begin
  mKey := KeyOf(AName);
  if not FValues.ContainsKey(mKey) then
  begin
    Exit;
  end;
  mValue.Raw := Trim(ARaw);
  if AOk then
  begin
    mValue.State := TAtlasInlineValueState.Ready;
    mValue.Text := Display(FTypes[mKey], mValue.Raw);
  end
  else if (FUnavailableText <> '') and TAtlasDebugUnavailable.IsUnavailable(mValue.Raw, FUnavailablePatterns) then
  begin
    mValue.State := TAtlasInlineValueState.Unavailable;
    mValue.Text := FUnavailableText;
  end
  else
  begin
    mValue.State := TAtlasInlineValueState.Failed;
    mValue.Text := '';
  end;
  FValues[mKey] := mValue;
end;

procedure TAtlasInlineValues.SetUnavailable(const AText: string; const APatterns: TArray<string>);
begin
  FUnavailableText := AText;
  FUnavailablePatterns := APatterns;
end;

function TAtlasInlineValues.Line(const AFileName: string; ALine: Integer): TAtlasInlineValueItems;
var
  mNames: TArray<string>;
  mKey, mPrevious: string;
  mValue: TValue;
  mItem: TAtlasInlineValueItem;
begin
  Result := nil;
  if (FOrder.Count = 0) or not SameText(AFileName, FFileName) or not FLines.TryGetValue(ALine, mNames) then
  begin
    Exit;
  end;
  for mKey in mNames do
  begin
    mValue := FValues[mKey];
    if not (mValue.State in [TAtlasInlineValueState.Ready, TAtlasInlineValueState.Unavailable]) then
    begin
      Continue;
    end;
    mItem.Name := FSpellings[mKey];
    mItem.Text := mValue.Text;
    mItem.State := mValue.State;
    mItem.Changed := (mValue.State = TAtlasInlineValueState.Ready) and FPrevious.TryGetValue(mKey, mPrevious) and
      (mPrevious <> mValue.Raw);
    Result := Result + [mItem];
  end;
end;

class function TAtlasInlineValues.Display(const ATypeName, ARaw: string): string;
var
  mKind: string;
  mNumber: Double;
  mInvariant: TFormatSettings;
begin
  Result := Trim(ARaw);
  mKind := LowerCase(ATypeName);
  if mKind.StartsWith('system.') then
  begin
    mKind := Copy(mKind, Length('system.') + 1, MaxInt);
  end;
  if (mKind = 'tdatetime') or (mKind = 'tdate') or (mKind = 'ttime') then
  begin
    mInvariant := TFormatSettings.Invariant;
    if TryStrToFloat(Result.Replace(',', '.'), mNumber, mInvariant) and (mNumber >= cMinDateTime) and
      (mNumber < cMaxDateTime) then
    begin
      if mKind = 'tdate' then
      begin
        Result := FormatDateTime('yyyy-mm-dd', mNumber, mInvariant);
      end
      else if mKind = 'ttime' then
      begin
        Result := FormatDateTime('hh:nn:ss', mNumber, mInvariant);
      end
      else if Frac(mNumber) = 0 then
      begin
        Result := FormatDateTime('yyyy-mm-dd', mNumber, mInvariant);
      end
      else
      begin
        Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', mNumber, mInvariant);
      end;
    end;
  end;
  // Zeilenumbrüche im Wert (mehrzeilige Strings) gehören nicht hinter das Zeilenende.
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
  Result := TAtlasDebugExpression.Shorten(Result, cMaxValueLength);
end;

class function TAtlasInlineValues.LineText(const AItems: TAtlasInlineValueItems): string;
var
  mItem: TAtlasInlineValueItem;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mItem.Caption;
  end;
end;

end.
