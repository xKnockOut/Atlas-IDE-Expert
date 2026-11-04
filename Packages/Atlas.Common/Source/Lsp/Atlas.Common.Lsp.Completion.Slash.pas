unit Atlas.Common.Lsp.Completion.Slash;

// Vervollständigung von Schnellbefehlen nach "/" am Zeilenanfang (#293) samt ihrer Argumente (#294 ff., #319)
// und in Compilerdirektiven (#102). Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionSlash = class
  public
    /// <summary>"/name" am Zeilenanfang (#293): die passenden, nicht abgeschalteten (ADisabled) Befehle; hinter
    /// dem Namen die Argumente des Befehls, für /ignore die Regeln aus ARuleIdsAt (#297). False außerhalb einer
    /// Codezeile oder ohne Vorschläge.</summary>
    class function SlashItems(ARequest: TCompletionRequest; const ADisabled: TArray<string>;
      const ARuleIdsAt: TSlashRuleIdsFunc; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Bedingte Symbole nach {$IFDEF , {$IFNDEF , {$DEFINE , {$UNDEF und in Defined( (#102): Herkunft als
    /// Detail, Symbole, die hier nicht gelten, abgeschwächt am Ende.</summary>
    class function SymbolItems(ARequest: TCompletionRequest; const AContext: TConditionalContext;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>Vorschläge in einer offenen Direktive (#102); False außerhalb.</summary>
    class function DirectiveItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.SlashMenu,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Lsp.CompilerDirectives,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Values,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Lines;

type
  /// <summary>Texte der Befehls- und Direktiven-Vervollständigung in beiden Sprachen (#1458).</summary>
  TSlashText = (CompilerWarning);

const
  cTexts: array[TSlashText] of TAtlasText = (
    (De: 'Compiler-Warnung'; En: 'Compiler warning'));

/// <summary>Kennungen des eingebauten Regelkatalogs für /ignore (#293); sonst leer.</summary>
function RuleIds(AKind: TSlashArgumentKind): TArray<string>;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  if AKind <> TSlashArgumentKind.Rules then
  begin
    Exit;
  end;
  mCatalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  try
    for mEntry in mCatalog.Entries do
    begin
      Result := Result + [mEntry.Id];
    end;
  finally
    mCatalog.Free;
  end;
end;

/// <summary>Für /ignore nur die Regeln, die in der Zeile unter dem Befehl treffen (#297); ohne Auskunft der
/// Katalog.</summary>
function RuleIdsBelow(ARequest: TCompletionRequest; AKind: TSlashArgumentKind;
  const ARuleIdsAt: TSlashRuleIdsFunc): TArray<string>;
var
  mLines: TArray<string>;
  mLineBreak: string;
  mLine: Integer;
begin
  if (AKind = TSlashArgumentKind.Rules) and Assigned(ARuleIdsAt) then
  begin
    // Ohne die Befehlszeile prüfen, wie nach dem Ausführen.
    mLines := TTextLines.SplitLines(ARequest.Text, mLineBreak);
    mLine := ARequest.Position.Line;
    if (mLine >= 0) and (mLine <= High(mLines)) then
    begin
      mLines[mLine] := StringOfChar(' ', Length(mLines[mLine]));
    end;
    if ARuleIdsAt(ARequest.Uri, TTextLines.JoinLines(mLines, mLineBreak), mLine + 1, Result) then
    begin
      Exit;
    end;
  end;
  Result := RuleIds(AKind);
end;

/// <summary>Steht der Cursor in einer Codezeile (nicht in Kommentar oder String)?</summary>
function InCodeLine(ARequest: TCompletionRequest): Boolean;
begin
  Result := TSlashCommandRegistry.IsCodeLine(TPascalLexer.Tokenize(ARequest.Text), ARequest.Position.Line);
end;

/// <summary>Einträge für die Argumente AChoices von /AName. Typen aus nicht eingebundenen Units bringen ihren
/// uses-Eintrag mit (#294, #180); dieser Fall läuft vor dem Syntaxbaum der Anfrage, daher ein eigener.</summary>
function ChoiceItems(ARequest: TCompletionRequest; const AName: string; AKind: TSlashArgumentKind;
  const AChoices: TArray<string>): TArray<TCompletionItem>;
var
  mLookup: TEnumLookup;
  mChoice: string;
  mItem: TCompletionItem;
begin
  Result := nil;
  mLookup := Default(TEnumLookup);
  mLookup.Index := ARequest.Index;
  mLookup.FileName := ARequest.FileName;
  if (AKind in [TSlashArgumentKind.Types, TSlashArgumentKind.Interfaces, TSlashArgumentKind.Exceptions]) and
    (ARequest.Index <> nil) and (Length(AChoices) > 0) then
  begin
    mLookup.Tree := TSyntaxTreeCache.Parse(ARequest.Text);
    mLookup.Resolver := TNameResolver.Create(ARequest.Index);
  end;
  try
    for mChoice in AChoices do
    begin
      mItem := Default(TCompletionItem);
      mItem.Name := mChoice;
      mItem.Kind := KindField;
      mItem.Detail := '/' + AName;
      if mLookup.Resolver <> nil then
      begin
        mItem.AdditionalEdits := TypeUnitEdits(mLookup, mChoice, ARequest.LineBreak,
          ARequest.OffsetAt(ARequest.Position));
      end;
      Result := Result + [mItem];
    end;
  finally
    mLookup.Resolver.Free;
    mLookup.Tree.Free;
  end;
end;

/// <summary>Hinter "/name ": die Argumente des Befehls; danach vervollständigen die Befehle selbst (#294 ff.),
/// /sort und /filter mit Sammlungen und Mitgliedern des Elementtyps (#319).</summary>
function ArgumentItems(ARequest: TCompletionRequest; const AName, AArguments: string;
  const ARuleIdsAt: TSlashRuleIdsFunc; out AItems: TCompletionItems): Boolean;
var
  mKind: TSlashArgumentKind;
begin
  AItems := Default(TCompletionItems);
  mKind := TSlashMenu.ArgumentKind(AName, AArguments);
  AItems.Items := ChoiceItems(ARequest, AName, mKind, TSlashMenu.ArgumentChoices(ARequest.Text,
    ARequest.Position.Line, AName, AArguments, ARequest.Index, RuleIdsBelow(ARequest, mKind, ARuleIdsAt)));
  Result := Length(AItems.Items) > 0;
end;

/// <summary>Die Befehle, die zu "/AName" passen.</summary>
function CommandItems(const AName: string; const ADisabled: TArray<string>): TArray<TCompletionItem>;
var
  mCommand: TSlashCommand;
  mItem: TCompletionItem;
begin
  Result := nil;
  for mCommand in TSlashCommandRegistry.Shared.Matching(AName, ADisabled) do
  begin
    mItem := Default(TCompletionItem);
    mItem.Name := mCommand.Name;
    mItem.Kind := KindKeyword;
    mItem.Detail := mCommand.Summary + ' – ' + mCommand.Example;
    mItem.InsertText := mCommand.Name + ' ';
    Result := Result + [mItem];
  end;
end;

{ TCompletionSlash }

class function TCompletionSlash.SlashItems(ARequest: TCompletionRequest; const ADisabled: TArray<string>;
  const ARuleIdsAt: TSlashRuleIdsFunc; out AItems: TCompletionItems): Boolean;
var
  mBefore, mName, mArguments: string;
begin
  AItems := Default(TCompletionItems);
  mBefore := ARequest.LineBefore;
  mName := '';
  mArguments := '';
  if (Trim(mBefore) <> '/') and not TSlashCommandRegistry.Split(mBefore, mName, mArguments) then
  begin
    Exit(False);
  end;
  if (mArguments <> '') or ((Trim(mBefore) <> '/') and (mBefore[Length(mBefore)] = ' ')) then
  begin
    Result := not MatchText(mName, ADisabled) and InCodeLine(ARequest) and
      ArgumentItems(ARequest, mName, mArguments, ARuleIdsAt, AItems);
    Exit;
  end;
  Result := InCodeLine(ARequest);
  if Result then
  begin
    AItems.Items := CommandItems(mName, ADisabled);
  end;
end;

class function TCompletionSlash.SymbolItems(ARequest: TCompletionRequest; const AContext: TConditionalContext;
  out AItems: TCompletionItems): Boolean;
var
  mPrefix: string;
  mSymbol: TConditionalSymbol;
  mItem: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := TConditionalSymbols.IsSymbolContext(ARequest.LineBefore, mPrefix);
  if not Result or not AContext.CompletionEnabled then
  begin
    Exit;
  end;
  for mSymbol in TConditionalSymbols.Candidates(ARequest.Text, AContext) do
  begin
    mItem := Default(TCompletionItem);
    mItem.Name := mSymbol.Name;
    mItem.Kind := KindConstant;
    mItem.Detail := mSymbol.Detail;
    mItem.Unavailable := not mSymbol.Active;
    AItems.Items := AItems.Items + [mItem];
  end;
end;

class function TCompletionSlash.DirectiveItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  mNames: TArray<string>;
  mIsWarning: Boolean;
  mName: string;
  mItem: TCompletionItem;
  mInfo: TDirectiveInfo;
begin
  AItems := Default(TCompletionItems);
  Result := TCompilerDirectives.CompletionAt(ARequest.LineBefore, mNames, mIsWarning);
  if not Result then
  begin
    Exit;
  end;
  for mName in mNames do
  begin
    mItem := Default(TCompletionItem);
    mItem.Name := mName;
    mItem.Kind := KindKeyword;
    if mIsWarning then
    begin
      mItem.Detail := cTexts[TSlashText.CompilerWarning].Text;
    end
    else if TCompilerDirectives.Find(mName, mInfo) then
    begin
      mItem.Detail := mInfo.Text;
    end;
    AItems.Items := AItems.Items + [mItem];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion.Slash', cTexts);

end.
