unit Atlas.Common.Lsp.Completion.Directives.Tests;

// Tests für Vorschläge in Compilerdirektiven (#102).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionDirectivesTests = class
  public
    /// <summary>Direktivennamen mit Beschreibung.</summary>
    [Test]
    procedure DirectiveNamesWithText;
    /// <summary>Bedingte Symbole des Compilers nach {$IFDEF .</summary>
    [Test]
    procedure SymbolsAfterIfdef;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Completion.Request,
  Atlas.Common.Lsp.Completion.Directives,
  Atlas.Common.Completion.Contract;

const
  cUnit =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'var'#10 +
    '  Wert: Integer;'#10 +
    'begin'#10 +
    '  %s'#10 +
    '  Wert := 42;'#10 +
    'end;'#10 +
    'end.';
  cCodeLine = 7;

/// <summary>Anfrage mit ALine an der Codezeile, Cursor am Zeilenende; der Aufrufer gibt sie frei.</summary>
function RequestFor(const ALine: string): TCompletionRequest;
begin
  Result := TCompletionRequest.Create(Format(cUnit, [ALine]), 'C:\P\Haupt.pas',
    TTextPosition.Create(cCodeLine, 2 + Length(ALine)));
end;

function Names(const AItems: TCompletionItems): TArray<string>;
var
  mItem: TCompletionItem;
begin
  Result := nil;
  for mItem in AItems.Items do
  begin
    Result := Result + [mItem.Name];
  end;
end;

{ TCompletionDirectivesTests }

procedure TCompletionDirectivesTests.DirectiveNamesWithText;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mFound: Boolean;
begin
  mRequest := RequestFor('{$DEFI');
  try
    Assert.IsTrue(TCompletionDirectives.DirectiveItems(mRequest, mItems));
    mFound := False;
    for mItem in mItems.Items do
    begin
      if mItem.Name = 'DEFINE' then
      begin
        mFound := True;
        Assert.AreNotEqual('', mItem.Detail, 'Beschreibung');
      end;
    end;
    Assert.IsTrue(mFound, string.Join(',', Names(mItems)));
  finally
    mRequest.Free;
  end;
  mRequest := RequestFor('Wert := 1;');
  try
    Assert.IsFalse(TCompletionDirectives.DirectiveItems(mRequest, mItems));
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionDirectivesTests.SymbolsAfterIfdef;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
  mContext: TConditionalContext;
begin
  mContext := Default(TConditionalContext);
  mContext.CompletionEnabled := True;
  mRequest := RequestFor('{$IFDEF ');
  try
    Assert.IsTrue(TCompletionDirectives.SymbolItems(mRequest, mContext, mItems));
    Assert.IsTrue(MatchText('MSWINDOWS', Names(mItems)), string.Join(',', Names(mItems)));
    mContext.CompletionEnabled := False;
    Assert.IsTrue(TCompletionDirectives.SymbolItems(mRequest, mContext, mItems));
    Assert.AreEqual(0, Integer(Length(mItems.Items)), 'abgeschaltet');
  finally
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionDirectivesTests);

end.
