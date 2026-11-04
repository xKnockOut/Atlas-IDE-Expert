unit Atlas.Core.Editor.Recursion;

// Rekursionssymbole im Editorrand (#623), ohne VCL und Open Tools API:
// - FromJson liest die Antwort von atlas.server.recursion
//   ({"calls": [{"line", "character", "endCharacter", "text", "chain": [{"name", "line", "character"}]}]},
//   Zeilen ab 0).
// - CallsAt: Aufrufe einer Zeile; Symbol nur, solange die Zeile im Editor noch
//   denselben Text hat wie beim Abruf (LineMatches).
// - TipText: Überschrift „Rekursion“ bzw. „Rekursion über n Methoden“, Text die
//   Kette; Links: je Methode der Kette einmal ihr Name, ein Klick springt zu ihr.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  TAtlasRecursionStep = record
    /// <summary>Name wie im Kopf, z. B. "TFoo.Speichern".</summary>
    Name: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

  TAtlasRecursionCall = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    EndCharacter: Integer;
    /// <summary>Kette als Text, z. B. "Speichern → Pruefen → Speichern".</summary>
    Text: string;
    Chain: TArray<TAtlasRecursionStep>;
    /// <summary>Anzahl verschiedener Methoden auf dem Kreis (1 = direkte Rekursion).</summary>
    function Methods: Integer;
  end;

  TAtlasFileRecursion = record
    Calls: TArray<TAtlasRecursionCall>;
    /// <summary>Antwort von atlas.server.recursion; leer bei unbekanntem Format.</summary>
    class function FromJson(AValue: TJSONValue): TAtlasFileRecursion; static;
    /// <summary>Aufrufe in ALine (0-basiert), von links nach rechts.</summary>
    function CallsAt(ALine: Integer): TArray<TAtlasRecursionCall>;
    function HasCalls: Boolean;
  end;

  TAtlasRecursionMarks = class
  public
    /// <summary>Zeile ALine (0-basiert) von AText; '' außerhalb.</summary>
    class function LineOf(const AText: string; ALine: Integer): string; static;
    /// <summary>Hat die Zeile im Editor noch den Text vom Abruf (ohne Leerraum am Ende)?</summary>
    class function LineMatches(const AEditorLine, AFetchedLine: string): Boolean; static;
    /// <summary>Überschrift und Text des Tooltips; ATitleDirect bzw. ATitleChain (mit %d für die Zahl der
    /// Methoden) aus den Texten der Oberfläche.</summary>
    class procedure TipText(const ACalls: TArray<TAtlasRecursionCall>; const ATitleDirect, ATitleChain: string;
      out ATitle, AText: string); static;
    /// <summary>Methoden der Ketten zum Anklicken, jede einmal, in der Reihenfolge der Ketten.</summary>
    class function Links(const ACalls: TArray<TAtlasRecursionCall>): TArray<TAtlasRecursionStep>; static;
  end;

implementation

{ TAtlasRecursionCall }

function TAtlasRecursionCall.Methods: Integer;
begin
  // Die Kette endet wieder bei der ersten Methode.
  Result := Length(Chain) - 1;
  if Result < 1 then
  begin
    Result := 1;
  end;
end;

{ TAtlasFileRecursion }

/// <summary>Kette {name, line, character} eines Aufrufs; Glieder ohne Namen fallen weg.</summary>
function ReadChain(const AValue: TJSONValue): TArray<TAtlasRecursionStep>;
var
  mLink: TJSONValue;
  mStep: TAtlasRecursionStep;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mLink in TJSONArray(AValue) do
    begin
      if mLink is TJSONObject then
      begin
        mStep.Name := TJSONObject(mLink).GetValue<string>('name', '');
        mStep.Line := TJSONObject(mLink).GetValue<Integer>('line', -1);
        mStep.Character := TJSONObject(mLink).GetValue<Integer>('character', 0);
        if mStep.Name <> '' then
        begin
          Result := Result + [mStep];
        end;
      end;
    end;
  end;
end;

/// <summary>Ein Aufruf {line, character, endCharacter, text, chain}; False ohne gültige Zeile.</summary>
function ReadCall(const AItem: TJSONObject; out ACall: TAtlasRecursionCall): Boolean;
begin
  ACall := Default(TAtlasRecursionCall);
  ACall.Line := AItem.GetValue<Integer>('line', -1);
  ACall.Character := AItem.GetValue<Integer>('character', 0);
  ACall.EndCharacter := AItem.GetValue<Integer>('endCharacter', ACall.Character);
  ACall.Text := AItem.GetValue<string>('text', '');
  Result := ACall.Line >= 0;
  if Result then
  begin
    ACall.Chain := ReadChain(AItem.GetValue('chain'));
  end;
end;

class function TAtlasFileRecursion.FromJson(AValue: TJSONValue): TAtlasFileRecursion;
var
  mItem: TJSONValue;
  mCall: TAtlasRecursionCall;
begin
  Result := Default(TAtlasFileRecursion);
  // Typen selbst prüfen: GetValue<TJSONArray> wandelt eine Zahl ungeprüft um.
  if (AValue is TJSONObject) and (TJSONObject(AValue).GetValue('calls') is TJSONArray) then
  begin
    for mItem in TJSONArray(TJSONObject(AValue).GetValue('calls')) do
    begin
      if (mItem is TJSONObject) and ReadCall(TJSONObject(mItem), mCall) then
      begin
        Result.Calls := Result.Calls + [mCall];
      end;
    end;
  end;
end;

function TAtlasFileRecursion.CallsAt(ALine: Integer): TArray<TAtlasRecursionCall>;
var
  Call: TAtlasRecursionCall;
  Index, Position: Integer;
begin
  Result := nil;
  for Call in Calls do
  begin
    if Call.Line = ALine then
    begin
      Position := Length(Result);
      for Index := 0 to High(Result) do
      begin
        if Call.Character < Result[Index].Character then
        begin
          Position := Index;
          Break;
        end;
      end;
      Insert(Call, Result, Position);
    end;
  end;
end;

function TAtlasFileRecursion.HasCalls: Boolean;
begin
  Result := Length(Calls) > 0;
end;

{ TAtlasRecursionMarks }

class function TAtlasRecursionMarks.LineOf(const AText: string; ALine: Integer): string;
var
  Index, Start, Line: Integer;
begin
  Result := '';
  if ALine < 0 then
  begin
    Exit;
  end;
  Line := 0;
  Start := 1;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = #10 then
    begin
      if Line = ALine then
      begin
        Exit(Copy(AText, Start, Index - Start).TrimRight([#13]));
      end;
      Inc(Line);
      Start := Index + 1;
    end;
  end;
  if Line = ALine then
  begin
    Result := Copy(AText, Start, MaxInt).TrimRight([#13]);
  end;
end;

class function TAtlasRecursionMarks.LineMatches(const AEditorLine, AFetchedLine: string): Boolean;
begin
  Result := TrimRight(AEditorLine) = TrimRight(AFetchedLine);
end;

class procedure TAtlasRecursionMarks.TipText(const ACalls: TArray<TAtlasRecursionCall>; const ATitleDirect,
  ATitleChain: string; out ATitle, AText: string);
var
  Call: TAtlasRecursionCall;
  Most: Integer;
begin
  ATitle := '';
  AText := '';
  Most := 0;
  for Call in ACalls do
  begin
    if Call.Methods > Most then
    begin
      Most := Call.Methods;
    end;
    if AText <> '' then
    begin
      AText := AText + #10;
    end;
    AText := AText + Call.Text;
  end;
  if Length(ACalls) = 0 then
  begin
    Exit;
  end;
  if Most <= 1 then
  begin
    ATitle := ATitleDirect;
  end
  else
  begin
    ATitle := Format(ATitleChain, [Most]);
  end;
end;

class function TAtlasRecursionMarks.Links(const ACalls: TArray<TAtlasRecursionCall>): TArray<TAtlasRecursionStep>;
var
  Call: TAtlasRecursionCall;
  Step, Known: TAtlasRecursionStep;
  Seen: Boolean;
begin
  Result := nil;
  for Call in ACalls do
  begin
    for Step in Call.Chain do
    begin
      Seen := False;
      for Known in Result do
      begin
        if SameText(Known.Name, Step.Name) then
        begin
          Seen := True;
        end;
      end;
      if not Seen and (Step.Line >= 0) then
      begin
        Result := Result + [Step];
      end;
    end;
  end;
end;

end.
