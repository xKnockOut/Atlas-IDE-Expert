unit Atlas.Core.Tests.ListText;

// Beschreibung und Prüfung einer Testliste (#2167) für das Fenster
// „Atlas-Tests“, ohne VCL und Open Tools API:
// - Describe: Kopfzeile des Reiters, die Regeln einer dynamischen Liste mit
//   „und“ verbunden („Kategorie ist nicht Benchmark und Stand ist
//   fehlgeschlagen“), bzw. die Zahl der Einträge einer festen. Die Texte in
//   der Sprache der Oberfläche gibt der Aufrufer (TAtlasTestListTexts).
// - Problem: was der Dialog vor dem Übernehmen meldet (Name fehlt oder ist
//   vergeben, dynamische Liste ohne Regel).

interface

uses
  Atlas.Core.Tests.Lists;

type
{$SCOPEDENUMS ON}
  /// <summary>Einwand gegen eine Liste im Dialog.</summary>
  TAtlasTestListProblem = (None, NameMissing, NameTaken, NoRule);
{$SCOPEDENUMS OFF}

  /// <summary>Texte der Beschreibung; %s bzw. %d wie angegeben.</summary>
  TAtlasTestListTexts = record
    /// <summary>Je Regelart [trifft zu, trifft nicht zu], mit %s für Kategorie, Muster bzw. Stand.</summary>
    Rules: array[TAtlasTestListRuleKind, Boolean] of string;
    States: array[TAtlasTestListState] of string;
    /// <summary>Verbindet zwei Regeln (mit Leerzeichen).</summary>
    AndText: string;
    /// <summary>Feste Liste, %d Einträge.</summary>
    Fixed: string;
  end;

  TAtlasTestListText = class
  public
    /// <summary>Regel ARule als Text.</summary>
    class function RuleText(const ARule: TAtlasTestListRule; const ATexts: TAtlasTestListTexts): string; static;
    /// <summary>Regeln bzw. Zahl der Einträge von AList.</summary>
    class function Describe(const AList: TAtlasTestList; const ATexts: TAtlasTestListTexts): string; static;
    /// <summary>Einwand gegen AList: Name leer bzw. unter ATaken (ohne Groß-/Kleinschreibung; die Namen der
    /// anderen Listen), dynamisch (ADynamic) ohne Regel.</summary>
    class function Problem(const AList: TAtlasTestList; ADynamic: Boolean;
      const ATaken: TArray<string>): TAtlasTestListProblem; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasTestListText.RuleText(const ARule: TAtlasTestListRule; const ATexts: TAtlasTestListTexts): string;
var
  mValue: string;
begin
  mValue := ARule.Value;
  if ARule.Kind = TAtlasTestListRuleKind.State then
  begin
    mValue := ATexts.States[ARule.State];
  end;
  Result := Format(ATexts.Rules[ARule.Kind, ARule.Exclude], [mValue]);
end;

class function TAtlasTestListText.Describe(const AList: TAtlasTestList; const ATexts: TAtlasTestListTexts): string;
var
  mRule: TAtlasTestListRule;
begin
  if not AList.IsDynamic then
  begin
    Exit(Format(ATexts.Fixed, [Length(AList.Tests)]));
  end;
  Result := '';
  for mRule in AList.Rules do
  begin
    if Result <> '' then
    begin
      Result := Result + ATexts.AndText;
    end;
    Result := Result + RuleText(mRule, ATexts);
  end;
end;

class function TAtlasTestListText.Problem(const AList: TAtlasTestList; ADynamic: Boolean;
  const ATaken: TArray<string>): TAtlasTestListProblem;
var
  mName: string;
begin
  if Trim(AList.Name) = '' then
  begin
    Exit(TAtlasTestListProblem.NameMissing);
  end;
  for mName in ATaken do
  begin
    if SameText(Trim(mName), Trim(AList.Name)) then
    begin
      Exit(TAtlasTestListProblem.NameTaken);
    end;
  end;
  Result := TAtlasTestListProblem.None;
  if ADynamic and (Length(AList.Rules) = 0) then
  begin
    Result := TAtlasTestListProblem.NoRule;
  end;
end;

end.
