unit Lsp.Completion.Directives;

// Vervollständigung in Compilerdirektiven (#102): bedingte Symbole und Direktivennamen. Teil der
// Vervollständigung (Lsp.Completion); die Schnellbefehle nach "/" liefert Editing als Quelle.

interface

{$SCOPEDENUMS ON}

uses
  Lsp.ConditionalSymbols,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Contract;

type
  TCompletionDirectives = class
  public
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
  Lsp.CompilerDirectives,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Direktiven-Vervollständigung in beiden Sprachen (#1458).</summary>
  TDirectiveText = (CompilerWarning);

const
  cTexts: array[TDirectiveText] of TAtlasText = (
    (De: 'Compiler-Warnung'; En: 'Compiler warning'));

{ TCompletionDirectives }

class function TCompletionDirectives.SymbolItems(ARequest: TCompletionRequest; const AContext: TConditionalContext;
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
    mItem.Kind := cKindConstant;
    mItem.Detail := mSymbol.Detail;
    mItem.Unavailable := not mSymbol.Active;
    AItems.Items := AItems.Items + [mItem];
  end;
end;

class function TCompletionDirectives.DirectiveItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
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
    mItem.Kind := cKindKeyword;
    if mIsWarning then
    begin
      mItem.Detail := cTexts[TDirectiveText.CompilerWarning].Text;
    end
    else if TCompilerDirectives.Find(mName, mInfo) then
    begin
      mItem.Detail := mInfo.Text;
    end;
    AItems.Items := AItems.Items + [mItem];
  end;
end;

initialization
  TAtlasTextTables.Add('Lsp.Completion.Directives', cTexts);

end.
