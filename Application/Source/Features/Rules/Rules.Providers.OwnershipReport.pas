unit Rules.Providers.OwnershipReport;

// Anbieter von IRuleOwnershipReport (Rules.Contract.Api) für den Befehl atlas.server.ownership
// [uri] (#1877): „Wer gibt das frei?“ für jede Erzeugung T.Create(…) der Unit, für die Marke am Zeilenende im
// Plugin. Die Einstufung kommt aus Rules.Ownership; „nie freigegeben“ nur dort, wo die Leck-Regeln
// (TOwnershipSites.cRuleIds) mit den Einstellungen der Datei einen Befund melden, damit Marke und Problem nie
// auseinanderlaufen. Text und Umfeld der Regeln liefert die Komposition (TRuleOwnershipInput).
//
// Antwort (Zeilen und Zeichen ab 0):
//   { uri, sites: [{line, character, endLine, endCharacter, lineText, className, target, kind, freeLine?, detail,
//                   container?, containerOwner?, rule?, message?}] }
// kind wie TOwnershipSites.cKindNames, container wie cContainerNames; freeLine
// nur bei destroy, finally und freed. lineText ist die Zeile der Erzeugung ohne
// Leerraum am Ende: Das Plugin zeichnet nur, solange die Zeile noch so lautet.
// Ist die Datei weder geöffnet noch lesbar, ist sites leer.

interface

uses
  System.JSON,
  Rules.Contract.Api,
  Rules.CheckContext,
  Rules.Ownership;

type
  /// <summary>Text der Datei (geöffnet vor Platte) und Umfeld der Prüfregeln zu AUri; False ohne Text.</summary>
  TRuleOwnershipInput = reference to function(const AUri: string; out AText: string;
    out ARules: TRuleCheckContext): Boolean;

  TRuleOwnershipReport = class(TInterfacedObject, IRuleOwnershipReport)
  private
    FInput: TRuleOwnershipInput;
  public
    constructor Create(const AInput: TRuleOwnershipInput);
    function Report(const AUri: string): TJSONObject;
    /// <summary>Stellen von AText (Umfeld ARules; ohne Regeln keine „nie freigegeben“).</summary>
    class function Sites(const AText: string; const ARules: TRuleCheckContext): TArray<TOwnershipSite>; static;
    /// <summary>Antwort zu AUri; der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AUri, AText: string; const ASites: TArray<TOwnershipSite>): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Text.Lines,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Rules.Contract;

/// <summary>Nur die Regeln, deren Befunde „nie freigegeben“ bedeuten.</summary>
function OwnershipRules(const ARules: TArray<IRule>): TArray<IRule>;
var
  mRule: IRule;
begin
  Result := nil;
  for mRule in ARules do
  begin
    if TOwnershipSites.IsOwnershipRule(mRule.Descriptor.Id) then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

function SiteToJson(const ASite: TOwnershipSite; const ALines: TArray<string>): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(ASite.Range.StartPos.Line));
  Result.AddPair('character', TJSONNumber.Create(ASite.Range.StartPos.Character));
  Result.AddPair('endLine', TJSONNumber.Create(ASite.Range.EndPos.Line));
  Result.AddPair('endCharacter', TJSONNumber.Create(ASite.Range.EndPos.Character));
  if (ASite.Range.StartPos.Line >= 0) and (ASite.Range.StartPos.Line < Length(ALines)) then
  begin
    Result.AddPair('lineText', TrimRight(ALines[ASite.Range.StartPos.Line]));
  end;
  Result.AddPair('className', ASite.ClassName);
  Result.AddPair('target', ASite.Target);
  Result.AddPair('kind', TOwnershipSites.cKindNames[ASite.Kind]);
  if ASite.FreeLine >= 0 then
  begin
    Result.AddPair('freeLine', TJSONNumber.Create(ASite.FreeLine));
  end;
  Result.AddPair('detail', ASite.Detail);
  if ASite.Container <> TOwnershipContainer.None then
  begin
    Result.AddPair('container', TOwnershipSites.cContainerNames[ASite.Container]);
    Result.AddPair('containerOwner', ASite.ContainerOwner);
  end;
  if ASite.Rule <> '' then
  begin
    Result.AddPair('rule', ASite.Rule);
  end;
  if ASite.Message <> '' then
  begin
    Result.AddPair('message', ASite.Message);
  end;
end;

{ TRuleOwnershipReport }

constructor TRuleOwnershipReport.Create(const AInput: TRuleOwnershipInput);
begin
  inherited Create;
  FInput := AInput;
end;

function TRuleOwnershipReport.Report(const AUri: string): TJSONObject;
var
  mText: string;
  mRules: TRuleCheckContext;
begin
  if not Assigned(FInput) or not FInput(AUri, mText, mRules) then
  begin
    Exit(ToJson(AUri, '', nil));
  end;
  Result := ToJson(AUri, mText, Sites(mText, mRules));
end;

class function TRuleOwnershipReport.Sites(const AText: string; const ARules: TRuleCheckContext): TArray<TOwnershipSite>;
var
  mRules: TRuleCheckContext;
  mTree: TSyntaxTree;
begin
  mRules := ARules;
  mRules.Rules := OwnershipRules(ARules.Rules);
  // Eigener Lauf nur dieser Regeln: Das Memo der Diagnose hält alle Regeln und kann einen anderen Text haben.
  mRules.Memo := nil;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    // Derselbe Kontext wie für die Regeln: Index, Nachladen und Namespaces klären gerufene Routinen anderer Units.
    Result := TOwnershipSites.Analyze(ARules.RuleContext(AText, mTree), mRules.Findings(AText, mTree));
  finally
    mTree.Free;
  end;
end;

class function TRuleOwnershipReport.ToJson(const AUri, AText: string; const ASites: TArray<TOwnershipSite>): TJSONObject;
var
  mItems: TJSONArray;
  mSite: TOwnershipSite;
  mLines: TArray<string>;
  mLineBreak: string;
begin
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  mItems := TJSONArray.Create;
  Result.AddPair('sites', mItems);
  for mSite in ASites do
  begin
    mItems.AddElement(SiteToJson(mSite, mLines));
  end;
end;

end.
