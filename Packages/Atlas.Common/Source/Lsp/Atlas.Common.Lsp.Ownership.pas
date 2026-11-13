unit Atlas.Common.Lsp.Ownership;

// Befehl atlas.server.ownership [uri] (#1877): „Wer gibt das frei?“ für jede
// Erzeugung T.Create(…) der Unit, für die Marke am Zeilenende im Plugin. Die
// Einstufung kommt aus Atlas.Common.Leaks.Ownership; „nie freigegeben“ nur dort,
// wo die Leck-Regeln (TOwnershipSites.cRuleIds) mit den Einstellungen der Datei
// einen Befund melden, damit Marke und Problem nie auseinanderlaufen.
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
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Leaks.Ownership;

type
  /// <summary>Text der Datei (geöffnet vor Platte) und Umfeld der Prüfregeln zu AUri; False ohne Text.</summary>
  TLspOwnershipInput = reference to function(const AUri: string; out AText: string;
    out ARules: TRuleCheckContext): Boolean;

  TLspOwnership = class
  public const
    cCommand = 'atlas.server.ownership';
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AInput: TLspOwnershipInput); static;
    /// <summary>Stellen von AText (Umfeld ARules; ohne Regeln keine „nie freigegeben“).</summary>
    class function Sites(const AText: string; const ARules: TRuleCheckContext): TArray<TOwnershipSite>; static;
    /// <summary>Antwort zu AUri; der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AUri, AText: string; const ASites: TArray<TOwnershipSite>): TJSONObject; static;
    /// <summary>atlas.server.ownership [uri]; EJsonRpcError ohne URI.</summary>
    class function Execute(const AArguments: TJSONArray; const AInput: TLspOwnershipInput): TJSONValue; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspOwnershipText = (NeedsUri);

const
  cTexts: array[TLspOwnershipText] of TAtlasText = (
    (De: '%s braucht die URI der Unit'; En: '%s needs the URI of the unit'));

{$SCOPEDENUMS OFF}

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

class function TLspOwnership.Sites(const AText: string; const ARules: TRuleCheckContext): TArray<TOwnershipSite>;
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
    Result := TOwnershipSites.Analyze(mTree, AText, ARules.Services.Index,
      TLspSyntaxDiagnostics.RuleFindings(AText, mTree, mRules));
  finally
    mTree.Free;
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

class function TLspOwnership.ToJson(const AUri, AText: string; const ASites: TArray<TOwnershipSite>): TJSONObject;
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

class function TLspOwnership.Execute(const AArguments: TJSONArray; const AInput: TLspOwnershipInput): TJSONValue;
var
  mUri, mText: string;
  mRules: TRuleCheckContext;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspOwnershipText.NeedsUri].Fmt([TLspOwnership.cCommand]));
  end;
  mUri := AArguments.Items[0].Value;
  if not AInput(mUri, mText, mRules) then
  begin
    Exit(ToJson(mUri, '', nil));
  end;
  Result := ToJson(mUri, mText, Sites(mText, mRules));
end;

class procedure TLspOwnership.Attach(ACommands: TLspCommands; const AInput: TLspOwnershipInput);
var
  mInput: TLspOwnershipInput;
begin
  mInput := AInput;
  ACommands.RegisterConcurrent(cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspOwnership.Execute(AArguments, mInput);
    end);
end;

end.
