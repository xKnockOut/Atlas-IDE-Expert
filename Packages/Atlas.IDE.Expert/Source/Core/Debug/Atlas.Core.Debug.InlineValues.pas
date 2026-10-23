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
    MaxValueLength = 40;
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
  System.Generics.Defaults,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Unavailable;

const
  // Gültige Tage von TDateTime (0001-01-01 bis 9999-12-31).
  MinDateTime = -693593.0;
  MaxDateTime = 2958466.0;

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
  Index: Integer;
begin
  Result := False;
  if (AName = '') or CharInSet(AName[1], ['0'..'9']) or TAtlasDebugExpression.IsReserved(AName) then
    Exit;
  for Index := 1 to Length(AName) do
    if not (CharInSet(AName[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AName[Index]) > 127)) then
      Exit;
  Result := True;
end;

procedure TAtlasInlineValues.Remember;
var
  Pair: TPair<string, TValue>;
begin
  if FValues.Count = 0 then
    Exit;
  if FPreviousContext <> FContext then
    FPrevious.Clear;
  FPreviousContext := FContext;
  for Pair in FValues do
    if Pair.Value.State = TAtlasInlineValueState.Ready then
      FPrevious.AddOrSetValue(Pair.Key, Pair.Value.Raw);
end;

procedure TAtlasInlineValues.Start(const AFileName, AContext: string; AStoppedLine: Integer;
  const ARefs: TAtlasInlineValueRefs; APerLine: Integer);
var
  Ref: TAtlasInlineValueRef;
  Sorted: TList<TAtlasInlineValueRef>;
  Names: TArray<string>;
  Key, Name: string;
  Seen: Boolean;
  Lines: TArray<Integer>;
  Line: Integer;
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
  if APerLine < 1 then
    APerLine := 1;
  Sorted := TList<TAtlasInlineValueRef>.Create;
  try
    for Ref in ARefs do
      if IsPlainIdentifier(Ref.Name) then
        Sorted.Add(Ref);
    // Reihenfolge im Text; der Server liefert sie schon so, aber darauf verlässt sich die Anzeige nicht.
    Sorted.Sort(TDelegatedComparer<TAtlasInlineValueRef>.Construct(
      function(const ALeft, ARight: TAtlasInlineValueRef): Integer
      begin
        Result := ALeft.Line - ARight.Line;
        if Result = 0 then
          Result := ALeft.Character - ARight.Character;
      end));
    for Ref in Sorted do
    begin
      Key := KeyOf(Ref.Name);
      if not FLines.TryGetValue(Ref.Line, Names) then
        Names := nil;
      if Length(Names) >= APerLine then
        Continue;
      Seen := False;
      for Name in Names do
        if Name = Key then
          Seen := True;
      if Seen then
        Continue;
      FLines.AddOrSetValue(Ref.Line, Names + [Key]);
      if not FTypes.ContainsKey(Key) then
      begin
        FTypes.Add(Key, Ref.TypeName);
        FSpellings.Add(Key, Ref.Name);
        FValues.Add(Key, Default(TValue));
      end;
    end;
  finally
    Sorted.Free;
  end;
  // Auswerten: Zeile des Halts zuerst, dann darüber die nächste zuerst.
  Lines := FLines.Keys.ToArray;
  TArray.Sort<Integer>(Lines, TDelegatedComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := Abs(ALeft - AStoppedLine) - Abs(ARight - AStoppedLine);
      if Result = 0 then
        Result := ARight - ALeft;
    end));
  for Line in Lines do
    for Key in FLines[Line] do
      if not FOrder.Contains(Key) then
        FOrder.Add(Key);
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
  Key: string;
begin
  AName := '';
  while FNext < FOrder.Count do
  begin
    Key := FOrder[FNext];
    if FValues[Key].State = TAtlasInlineValueState.Pending then
    begin
      AName := FSpellings[Key];
      Exit(True);
    end;
    Inc(FNext);
  end;
  Result := False;
end;

procedure TAtlasInlineValues.Put(const AName, ARaw: string; AOk: Boolean);
var
  Key: string;
  Value: TValue;
begin
  Key := KeyOf(AName);
  if not FValues.ContainsKey(Key) then
    Exit;
  Value.Raw := Trim(ARaw);
  if AOk then
  begin
    Value.State := TAtlasInlineValueState.Ready;
    Value.Text := Display(FTypes[Key], Value.Raw);
  end
  else if (FUnavailableText <> '') and TAtlasDebugUnavailable.IsUnavailable(Value.Raw, FUnavailablePatterns) then
  begin
    Value.State := TAtlasInlineValueState.Unavailable;
    Value.Text := FUnavailableText;
  end
  else
  begin
    Value.State := TAtlasInlineValueState.Failed;
    Value.Text := '';
  end;
  FValues[Key] := Value;
end;

procedure TAtlasInlineValues.SetUnavailable(const AText: string; const APatterns: TArray<string>);
begin
  FUnavailableText := AText;
  FUnavailablePatterns := APatterns;
end;

function TAtlasInlineValues.Line(const AFileName: string; ALine: Integer): TAtlasInlineValueItems;
var
  Names: TArray<string>;
  Key, Previous: string;
  Value: TValue;
  Item: TAtlasInlineValueItem;
begin
  Result := nil;
  if (FOrder.Count = 0) or not SameText(AFileName, FFileName) or not FLines.TryGetValue(ALine, Names) then
    Exit;
  for Key in Names do
  begin
    Value := FValues[Key];
    if not (Value.State in [TAtlasInlineValueState.Ready, TAtlasInlineValueState.Unavailable]) then
      Continue;
    Item.Name := FSpellings[Key];
    Item.Text := Value.Text;
    Item.State := Value.State;
    Item.Changed := (Value.State = TAtlasInlineValueState.Ready) and FPrevious.TryGetValue(Key, Previous) and
      (Previous <> Value.Raw);
    Result := Result + [Item];
  end;
end;

class function TAtlasInlineValues.Display(const ATypeName, ARaw: string): string;
var
  Kind: string;
  Number: Double;
  Invariant: TFormatSettings;
begin
  Result := Trim(ARaw);
  Kind := LowerCase(ATypeName);
  if Kind.StartsWith('system.') then
    Kind := Copy(Kind, Length('system.') + 1, MaxInt);
  if (Kind = 'tdatetime') or (Kind = 'tdate') or (Kind = 'ttime') then
  begin
    Invariant := TFormatSettings.Invariant;
    if TryStrToFloat(Result.Replace(',', '.'), Number, Invariant) and (Number >= MinDateTime) and
      (Number < MaxDateTime) then
    begin
      if Kind = 'tdate' then
        Result := FormatDateTime('yyyy-mm-dd', Number, Invariant)
      else if Kind = 'ttime' then
        Result := FormatDateTime('hh:nn:ss', Number, Invariant)
      else if Frac(Number) = 0 then
        Result := FormatDateTime('yyyy-mm-dd', Number, Invariant)
      else
        Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', Number, Invariant);
    end;
  end;
  // Zeilenumbrüche im Wert (mehrzeilige Strings) gehören nicht hinter das Zeilenende.
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
  Result := TAtlasDebugExpression.Shorten(Result, MaxValueLength);
end;

class function TAtlasInlineValues.LineText(const AItems: TAtlasInlineValueItems): string;
var
  Item: TAtlasInlineValueItem;
begin
  Result := '';
  for Item in AItems do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Item.Caption;
  end;
end;

end.
