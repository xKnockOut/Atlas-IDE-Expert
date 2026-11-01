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
    Result := 1;
end;

{ TAtlasFileRecursion }

class function TAtlasFileRecursion.FromJson(AValue: TJSONValue): TAtlasFileRecursion;
var
  Calls, Chain: TJSONArray;
  Item, Link: TJSONValue;
  Call: TAtlasRecursionCall;
  Step: TAtlasRecursionStep;
begin
  Result := Default(TAtlasFileRecursion);
  if not (AValue is TJSONObject) then
    Exit;
  // Typen selbst prüfen: GetValue<TJSONArray> wandelt eine Zahl ungeprüft um.
  if not (TJSONObject(AValue).GetValue('calls') is TJSONArray) then
    Exit;
  Calls := TJSONArray(TJSONObject(AValue).GetValue('calls'));
  for Item in Calls do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Call := Default(TAtlasRecursionCall);
    Call.Line := TJSONObject(Item).GetValue<Integer>('line', -1);
    Call.Character := TJSONObject(Item).GetValue<Integer>('character', 0);
    Call.EndCharacter := TJSONObject(Item).GetValue<Integer>('endCharacter', Call.Character);
    Call.Text := TJSONObject(Item).GetValue<string>('text', '');
    if Call.Line < 0 then
      Continue;
    if TJSONObject(Item).GetValue('chain') is TJSONArray then
    begin
      Chain := TJSONArray(TJSONObject(Item).GetValue('chain'));
      for Link in Chain do
        if Link is TJSONObject then
        begin
          Step.Name := TJSONObject(Link).GetValue<string>('name', '');
          Step.Line := TJSONObject(Link).GetValue<Integer>('line', -1);
          Step.Character := TJSONObject(Link).GetValue<Integer>('character', 0);
          if Step.Name <> '' then
            Call.Chain := Call.Chain + [Step];
        end;
    end;
    Result.Calls := Result.Calls + [Call];
  end;
end;

function TAtlasFileRecursion.CallsAt(ALine: Integer): TArray<TAtlasRecursionCall>;
var
  Call: TAtlasRecursionCall;
  Index, Position: Integer;
begin
  Result := nil;
  for Call in Calls do
    if Call.Line = ALine then
    begin
      Position := Length(Result);
      for Index := 0 to High(Result) do
        if Call.Character < Result[Index].Character then
        begin
          Position := Index;
          Break;
        end;
      Insert(Call, Result, Position);
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
    Exit;
  Line := 0;
  Start := 1;
  for Index := 1 to Length(AText) do
    if AText[Index] = #10 then
    begin
      if Line = ALine then
        Exit(Copy(AText, Start, Index - Start).TrimRight([#13]));
      Inc(Line);
      Start := Index + 1;
    end;
  if Line = ALine then
    Result := Copy(AText, Start, MaxInt).TrimRight([#13]);
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
      Most := Call.Methods;
    if AText <> '' then
      AText := AText + #10;
    AText := AText + Call.Text;
  end;
  if Length(ACalls) = 0 then
    Exit;
  if Most <= 1 then
    ATitle := ATitleDirect
  else
    ATitle := Format(ATitleChain, [Most]);
end;

class function TAtlasRecursionMarks.Links(const ACalls: TArray<TAtlasRecursionCall>): TArray<TAtlasRecursionStep>;
var
  Call: TAtlasRecursionCall;
  Step, Known: TAtlasRecursionStep;
  Seen: Boolean;
begin
  Result := nil;
  for Call in ACalls do
    for Step in Call.Chain do
    begin
      Seen := False;
      for Known in Result do
        if SameText(Known.Name, Step.Name) then
          Seen := True;
      if not Seen and (Step.Line >= 0) then
        Result := Result + [Step];
    end;
end;

end.
