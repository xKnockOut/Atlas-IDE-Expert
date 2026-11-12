unit Atlas.Core.Problems.Explanation;

// „Regel erklären“ (#909) im Fenster „Atlas-Prüfung“: Katalogtext einer Regel
// aus der Antwort von atlas.server.settingsCatalog ({"rules": [{"id": …,
// "name": …, "description": …, "bad": …, "good": …, "experimental": …}]}).
// Erklären bleibt in Base (#1755): Es braucht nur den Katalog des Servers,
// nicht die Regeltabelle des Moduls Prüfregeln.
// Compilermeldungen (#54) stehen in derselben Antwort unter "messages"
// ({"code": "E2003", "name", "description", "cause", "bad", "good", "docWiki"});
// Find sucht Regeln nach "id" und Meldungen nach "code". MessageCode liefert die
// Nummer einer Compiler- bzw. IDE-Meldung, Key den Schlüssel für Find.

interface

uses
  System.JSON,
  Atlas.Core.Lsp.Contract;

type
  /// <summary>Katalogtext einer Regel oder Compilermeldung (atlas.server.settingsCatalog).</summary>
  TAtlasRuleExplanation = record
    /// <summary>Regel-ID bzw. Meldungsnummer (E2003).</summary>
    Id: string;
    Name: string;
    Description: string;
    /// <summary>Typische Ursache einer Compilermeldung (#54); '' bei Regeln.</summary>
    Cause: string;
    Bad: string;
    Good: string;
    /// <summary>Link ins DocWiki (#54); '' bei Regeln.</summary>
    DocWiki: string;
    Experimental: Boolean;
    /// <summary>Eintrag von AKey (Regel-ID oder Meldungsnummer, Groß-/Kleinschreibung egal) aus ACatalog (darf nil
    /// sein); False ohne ihn.</summary>
    class function Find(ACatalog: TJSONValue; const AKey: string; out AExplanation: TAtlasRuleExplanation): Boolean;
      static;
    /// <summary>Nummer einer Compiler- bzw. IDE-Meldung (E2003, W1036): Code, wenn er so aussieht, sonst aus dem
    /// Meldungstext; '' bei Regelbefunden und ohne Nummer.</summary>
    class function MessageCode(const AProblem: TAtlasProblem): string; static;
    /// <summary>Schlüssel für Find: Meldungsnummer, sonst die Regel-ID; '' ohne.</summary>
    class function Key(const AProblem: TAtlasProblem): string; static;
    /// <summary>Zeilen eines Beispiels (Bad, Good) für die Anzeige (#145): ohne Leerzeilen am Ende, Tabulatoren als
    /// zwei Leerzeichen; mehr als AMaxLines Zeilen gekürzt auf AMaxLines - 1 und „…“.</summary>
    class function ExampleLines(const ACode: string; AMaxLines: Integer): TArray<string>; static;
  end;

  /// <summary>Katalogtext einer Regel, im Hauptthread; Id = '' ohne Eintrag oder ohne Server (#145).</summary>
  TAtlasRuleExplanationEvent = reference to procedure(const AExplanation: TAtlasRuleExplanation);

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

/// <summary>Eintrag mit AField = AKey in der Liste AList von ACatalog; nil ohne.</summary>
function CatalogItem(ACatalog: TJSONValue; const AList, AField, AKey: string): TJSONObject;
var
  mItems, mItem: TJSONValue;
begin
  Result := nil;
  if not (ACatalog is TJSONObject) then
  begin
    Exit;
  end;
  mItems := TJSONObject(ACatalog).GetValue(AList);
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if (mItem is TJSONObject) and SameText(TJSONObject(mItem).GetValue<string>(AField, ''), AKey) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

const
  /// <summary>Ziffern einer Meldungsnummer (E2003) bzw. ihre ganze Länge.</summary>
  cCodeDigits = 4;
  cCodeLength = cCodeDigits + 1;

/// <summary>Steht ab AStart in AText eine Nummer wie E2003 (Buchstabe E, W, H oder F und vier Ziffern) als
/// eigenes Wort?</summary>
function IsCodeAt(const AText: string; AStart: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := (AStart + cCodeDigits <= Length(AText)) and CharInSet(UpCase(AText[AStart]), ['E', 'W', 'H', 'F']) and
    ((AStart = 1) or not CharInSet(AText[AStart - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := AStart + 1 to AStart + cCodeDigits do
  begin
    if not CharInSet(AText[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
  Result := (AStart + cCodeLength > Length(AText)) or
    not CharInSet(AText[AStart + cCodeLength], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

/// <summary>Erste Nummer in AText; '' ohne.</summary>
function FirstCode(const AText: string): string;
var
  mStart: Integer;
begin
  for mStart := 1 to Length(AText) do
  begin
    if IsCodeAt(AText, mStart) then
    begin
      Exit(UpperCase(Copy(AText, mStart, cCodeLength)));
    end;
  end;
  Result := '';
end;

{ TAtlasRuleExplanation }

class function TAtlasRuleExplanation.Find(ACatalog: TJSONValue; const AKey: string;
  out AExplanation: TAtlasRuleExplanation): Boolean;
var
  mItem: TJSONObject;
begin
  AExplanation := Default(TAtlasRuleExplanation);
  mItem := nil;
  if AKey <> '' then
  begin
    mItem := CatalogItem(ACatalog, 'rules', 'id', AKey);
    if mItem = nil then
    begin
      mItem := CatalogItem(ACatalog, 'messages', 'code', AKey);
    end;
  end;
  Result := mItem <> nil;
  if not Result then
  begin
    Exit;
  end;
  AExplanation.Id := mItem.GetValue<string>('id', mItem.GetValue<string>('code', ''));
  AExplanation.Name := mItem.GetValue<string>('name', '');
  AExplanation.Description := mItem.GetValue<string>('description', '');
  AExplanation.Cause := mItem.GetValue<string>('cause', '');
  AExplanation.Bad := mItem.GetValue<string>('bad', '');
  AExplanation.Good := mItem.GetValue<string>('good', '');
  AExplanation.DocWiki := mItem.GetValue<string>('docWiki', '');
  AExplanation.Experimental := mItem.GetValue<Boolean>('experimental', False);
end;

class function TAtlasRuleExplanation.MessageCode(const AProblem: TAtlasProblem): string;
begin
  Result := '';
  if not AProblem.IsCompiler and not AProblem.IsIde then
  begin
    Exit;
  end;
  if (Length(AProblem.Code) = cCodeLength) and IsCodeAt(AProblem.Code, 1) then
  begin
    Exit(UpperCase(AProblem.Code));
  end;
  Result := FirstCode(AProblem.Message);
end;

class function TAtlasRuleExplanation.Key(const AProblem: TAtlasProblem): string;
begin
  Result := MessageCode(AProblem);
  if (Result = '') and not AProblem.IsCompiler and not AProblem.IsIde then
  begin
    Result := AProblem.Code;
  end;
end;

class function TAtlasRuleExplanation.ExampleLines(const ACode: string; AMaxLines: Integer): TArray<string>;
var
  mLines: TArray<string>;
  mCount, mShown, mLine: Integer;
begin
  mLines := ACode.Replace(#13, '').Replace(#9, '  ').Split([#10]);
  mCount := Length(mLines);
  while (mCount > 0) and (Trim(mLines[mCount - 1]) = '') do
  begin
    Dec(mCount);
  end;
  mShown := mCount;
  if (AMaxLines > 0) and (mCount > AMaxLines) then
  begin
    mShown := AMaxLines;
  end;
  SetLength(Result, mShown);
  for mLine := 0 to mShown - 1 do
  begin
    Result[mLine] := mLines[mLine];
  end;
  if mShown < mCount then
  begin
    Result[mShown - 1] := '…';
  end;
end;

end.
