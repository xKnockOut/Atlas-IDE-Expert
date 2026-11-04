unit Atlas.Common.Lsp.Completion.InheritedCalls;

// Vollständige inherited-Aufrufe (#482) nach "inherited " vor den Namen der Vorfahrmethoden. Die Teile ohne
// Namensauflösung stehen in Atlas.Common.Lsp.CompletionInherited. Aus Atlas.Common.Lsp.Completion
// herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionCollector;

type
  TCompletionInheritedCalls = class
  public
    /// <summary>Fügt die vollständigen inherited-Aufrufe in ACollector ein, vor allen übrigen Einträgen; aus
    /// ACandidates fallen die abstrakten und die, deren Aufruf schon oben steht.</summary>
    class procedure Add(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      ACollector: TCompletionCollector; var ACandidates: TArray<TResolvedSymbol>); static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionInherited;

const
  /// <summary>Vor allen übrigen Einträgen, in der Reihenfolge der Aufrufe.</summary>
  cCallBonus = 100000;

type
  /// <summary>Die Methode, in der "inherited" steht, und was für die Einträge gilt.</summary>
  TInheritedSite = record
    Current: TInheritedHeader;
    Calls: TArray<TInheritedCall>;
    /// <summary>Abstrakte Vorfahrmethoden (Container.Name) für die Fußzeile.</summary>
    Abstracts: TArray<string>;
    LineBefore: string;
    WithResult: Boolean;
    /// <summary>Semikolon nur, wenn hinter dem Cursor nichts mehr steht.</summary>
    Semicolon: Boolean;
  end;

/// <summary>Überladungen der Vorfahren mit lesbarem Kopf.</summary>
function InheritedMethods(const ASymbols: TArray<TIndexSymbol>; const ADepths: TArray<Integer>):
  TArray<TInheritedMethod>;
var
  mIndex: Integer;
  mHeader: TInheritedHeader;
  mMethod: TInheritedMethod;
begin
  Result := nil;
  for mIndex := 0 to High(ASymbols) do
  begin
    if TInheritedHeader.Parse(ASymbols[mIndex].Signature, mHeader) then
    begin
      mMethod.Header := mHeader;
      mMethod.Container := ASymbols[mIndex].Container;
      mMethod.Depth := ADepths[mIndex];
      Result := Result + [mMethod];
    end;
  end;
end;

/// <summary>Kopf der umgebenden Methode und die passenden Aufrufe; False ohne.</summary>
function InheritedSiteAt(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  out ASite: TInheritedSite): Boolean;
var
  mSymbols: TArray<TIndexSymbol>;
  mDepths: TArray<Integer>;
  mStart: Integer;
begin
  ASite := Default(TInheritedSite);
  mSymbols := ARequest.Resolver.Queries.InheritedOverloads(ARequest.Tree, ARequest.FileName, AContext.Offset, mStart,
    mDepths);
  Result := (mStart >= 0) and TInheritedHeader.Parse(TCompletionInherited.HeaderText(ARequest.Text, mStart + 1),
    ASite.Current);
  if not Result then
  begin
    Exit;
  end;
  ASite.Calls := TCompletionInherited.Calls(ASite.Current, InheritedMethods(mSymbols, mDepths), ASite.Abstracts);
  ASite.LineBefore := ARequest.LineBefore;
  ASite.WithResult := TCompletionInherited.NeedsResult(ASite.Current, ASite.LineBefore);
  ASite.Semicolon := Trim(Copy(ARequest.LineText(ARequest.Position.Line), ARequest.Position.Character + 1,
    MaxInt)) = '';
end;

/// <summary>Unter den Namen fallen die abstrakten weg (auch für die Fußzeile) und die, deren Aufruf oben steht.
/// </summary>
procedure KeepCandidates(var ASite: TInheritedSite; var ACandidates: TArray<TResolvedSymbol>);
var
  mNames: TArray<string>;
  mKept: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mHeader: TInheritedHeader;
  mCall: TInheritedCall;
  mName: string;
begin
  mNames := nil;
  for mCall in ASite.Calls do
  begin
    mNames := mNames + [mCall.Name];
  end;
  mKept := nil;
  for mCandidate in ACandidates do
  begin
    mName := mCandidate.Container + '.' + mCandidate.Name;
    if not TInheritedHeader.Parse(mCandidate.Signature, mHeader) or not mHeader.IsAbstract then
    begin
      if not MatchText(mCandidate.Name, mNames) then
      begin
        mKept := mKept + [mCandidate];
      end;
    end
    else if not MatchText(mName, ASite.Abstracts) then
    begin
      ASite.Abstracts := ASite.Abstracts + [mName];
    end;
  end;
  ACandidates := mKept;
end;

/// <summary>Eintrag für den Aufruf ACall.</summary>
function CallItem(ARequest: TCompletionRequest; const AContext: TCompletionContext; const ASite: TInheritedSite;
  const ACall: TInheritedCall): TCompletionItem;
var
  mText: string;
  mColumn: Integer;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACall.Text;
  Result.FilterText := ACall.Name;
  Result.Detail := ACall.Container;
  Result.Kind := KindMethod;
  if ASite.Current.Kind = 'constructor' then
  begin
    Result.Kind := KindConstructor;
  end;
  Result.Container := ACall.Container;
  Result.Depth := ACall.Depth;
  Result.InheritedMatch := TCompletionInherited.MatchNames[ACall.Match];
  Result.InheritedAbstract := ASite.Abstracts;
  mText := ACall.Text;
  if ASite.Semicolon then
  begin
    mText := mText + ';';
  end;
  Result.HasTextEdit := True;
  if ASite.WithResult then
  begin
    mColumn := Pos('inherited', LowerCase(ASite.LineBefore)) - 1;
    Result.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line, mColumn, ARequest.Position.Line,
      ARequest.Position.Character), 'Result := inherited ' + mText);
  end
  else
  begin
    Result.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line,
      ARequest.Position.Character - Length(AContext.Prefix), ARequest.Position.Line, ARequest.Position.Character),
      mText);
  end;
end;

class procedure TCompletionInheritedCalls.Add(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  ACollector: TCompletionCollector; var ACandidates: TArray<TResolvedSymbol>);
var
  mSite: TInheritedSite;
  mIndex, mScore: Integer;
begin
  if not InheritedSiteAt(ARequest, AContext, mSite) then
  begin
    Exit;
  end;
  KeepCandidates(mSite, ACandidates);
  for mIndex := 0 to High(mSite.Calls) do
  begin
    mScore := MatchScore(mSite.Calls[mIndex].Name, AContext.Prefix, ARequest.Matching);
    if mScore <> TFuzzyMatch.NoMatch then
    begin
      ACollector.AddItem(CallItem(ARequest, AContext, mSite, mSite.Calls[mIndex]), mScore + cCallBonus - mIndex);
    end;
  end;
end;

end.
