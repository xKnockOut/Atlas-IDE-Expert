unit Editing.Completion.Slash;

// Vervollständigung von Schnellbefehlen nach "/" am Zeilenanfang (#293) samt ihrer Argumente (#294 ff., #319).
// Editing meldet sie als Quelle an der Stelle TCompletionSlot.Slash an; der Sprachserver kennt die Befehle nicht.

interface

uses
  Editing.Contract,
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer;

type
  TEditingSlashCompletion = class
  public
    /// <summary>"/name" am Zeilenanfang (#293): die passenden, nicht abgeschalteten (ADisabled) Befehle; hinter
    /// dem Namen die Argumente des Befehls, für /ignore die Regeln aus ARuleIdsAt (#297), ohne Auskunft die aus
    /// ACatalogIds (nicht zugewiesen = keine). False außerhalb einer Codezeile oder ohne Vorschläge.</summary>
    class function Items(ARequest: TCompletionRequest; const ADisabled: TArray<string>;
      const ARuleIdsAt: TSlashRuleIdsFunc; const ACatalogIds: TSlashCatalogIdsFunc;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>Quelle für TCompletionSlot.Slash: antwortet allein mit Items. ACommandsFor nennt die
    /// abgeschalteten Befehle; liefert es False, sind alle aus.</summary>
    class function Source(const ACommandsFor: TSlashCommandsProvider; const ARuleIdsAt: TSlashRuleIdsFunc;
      const ACatalogIds: TSlashCatalogIdsFunc): TCompletionSource; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.CommandLines,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeImports,
  Editing.SlashCommands,
  Editing.SlashMenu,
  Atlas.Text.Lines;

/// <summary>Kennungen des eingebauten Regelkatalogs für /ignore (#293); sonst oder ohne ACatalogIds leer.
/// </summary>
function RuleIds(AKind: TSlashArgumentKind; const ACatalogIds: TSlashCatalogIdsFunc): TArray<string>;
begin
  Result := nil;
  if (AKind = TSlashArgumentKind.Rules) and Assigned(ACatalogIds) then
  begin
    Result := ACatalogIds();
  end;
end;

/// <summary>Für /ignore nur die Regeln, die in der Zeile unter dem Befehl treffen (#297); ohne Auskunft der
/// Katalog.</summary>
function RuleIdsBelow(ARequest: TCompletionRequest; AKind: TSlashArgumentKind;
  const ARuleIdsAt: TSlashRuleIdsFunc; const ACatalogIds: TSlashCatalogIdsFunc): TArray<string>;
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
  Result := RuleIds(AKind, ACatalogIds);
end;

/// <summary>Steht der Cursor in einer Codezeile (nicht in Kommentar oder String)?</summary>
function InCodeLine(ARequest: TCompletionRequest): Boolean;
begin
  Result := TPascalCommandLines.IsCodeLine(TPascalLexer.Tokenize(ARequest.Text), ARequest.Position.Line);
end;

/// <summary>Einträge für die Argumente AChoices von /AName. Typen aus nicht eingebundenen Units bringen ihren
/// uses-Eintrag mit (#294, #180); dieser Fall läuft vor dem Syntaxbaum der Anfrage, daher ein eigener.</summary>
function ChoiceItems(ARequest: TCompletionRequest; const AName: string; AKind: TSlashArgumentKind;
  const AChoices: TArray<string>): TArray<TCompletionItem>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mChoice: string;
  mItem: TCompletionItem;
begin
  Result := nil;
  mTree := nil;
  mResolver := nil;
  if (AKind in [TSlashArgumentKind.Types, TSlashArgumentKind.Interfaces, TSlashArgumentKind.Exceptions]) and
    (ARequest.Index <> nil) and (Length(AChoices) > 0) then
  begin
    mTree := TSyntaxTreeCache.Parse(ARequest.Text);
    mResolver := TNameResolver.Create(ARequest.Index);
  end;
  try
    for mChoice in AChoices do
    begin
      mItem := Default(TCompletionItem);
      mItem.Name := mChoice;
      mItem.Kind := cKindField;
      mItem.Detail := '/' + AName;
      if mResolver <> nil then
      begin
        mItem.AdditionalEdits := TTypeImports.Edits(mResolver, ARequest.Index, mTree, ARequest.FileName, mChoice,
          ARequest.LineBreak, ARequest.OffsetAt(ARequest.Position));
      end;
      Result := Result + [mItem];
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

/// <summary>Hinter "/name ": die Argumente des Befehls; danach vervollständigen die Befehle selbst (#294 ff.),
/// /sort und /filter mit Sammlungen und Mitgliedern des Elementtyps (#319).</summary>
function ArgumentItems(ARequest: TCompletionRequest; const AName, AArguments: string;
  const ARuleIdsAt: TSlashRuleIdsFunc; const ACatalogIds: TSlashCatalogIdsFunc;
  out AItems: TCompletionItems): Boolean;
var
  mKind: TSlashArgumentKind;
begin
  AItems := Default(TCompletionItems);
  mKind := TSlashMenu.ArgumentKind(AName, AArguments);
  AItems.Items := ChoiceItems(ARequest, AName, mKind, TSlashMenu.ArgumentChoices(ARequest.Text,
    ARequest.Position.Line, AName, AArguments, ARequest.Index, RuleIdsBelow(ARequest, mKind, ARuleIdsAt,
    ACatalogIds)));
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
    mItem.Kind := cKindKeyword;
    mItem.Detail := mCommand.Summary + ' – ' + mCommand.Example;
    mItem.InsertText := mCommand.Name + ' ';
    Result := Result + [mItem];
  end;
end;

{ TEditingSlashCompletion }

class function TEditingSlashCompletion.Items(ARequest: TCompletionRequest; const ADisabled: TArray<string>;
  const ARuleIdsAt: TSlashRuleIdsFunc; const ACatalogIds: TSlashCatalogIdsFunc;
  out AItems: TCompletionItems): Boolean;
var
  mBefore, mName, mArguments: string;
begin
  AItems := Default(TCompletionItems);
  mBefore := ARequest.LineBefore;
  mName := '';
  mArguments := '';
  if (Trim(mBefore) <> '/') and not TPascalCommandLines.Split(mBefore, mName, mArguments) then
  begin
    Exit(False);
  end;
  if (mArguments <> '') or ((Trim(mBefore) <> '/') and (mBefore[Length(mBefore)] = ' ')) then
  begin
    Result := not MatchText(mName, ADisabled) and InCodeLine(ARequest) and
      ArgumentItems(ARequest, mName, mArguments, ARuleIdsAt, ACatalogIds, AItems);
    Exit;
  end;
  Result := InCodeLine(ARequest);
  if Result then
  begin
    AItems.Items := CommandItems(mName, ADisabled);
  end;
end;

class function TEditingSlashCompletion.Source(const ACommandsFor: TSlashCommandsProvider;
  const ARuleIdsAt: TSlashRuleIdsFunc; const ACatalogIds: TSlashCatalogIdsFunc): TCompletionSource;
begin
  Result :=
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      mDisabled: TArray<string>;
    begin
      Result := TCompletionOutcome.Next;
      mDisabled := nil;
      if (not Assigned(ACommandsFor) or ACommandsFor(ARequest.Uri, mDisabled)) and
        Items(ARequest, mDisabled, ARuleIdsAt, ACatalogIds, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end;
end;

end.
