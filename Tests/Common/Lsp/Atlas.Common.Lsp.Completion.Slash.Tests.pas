unit Atlas.Common.Lsp.Completion.Slash.Tests;

// Tests für Schnellbefehle nach "/" (#293 ff.) und Vorschläge in Compilerdirektiven (#102).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionSlashTests = class
  public
    /// <summary>"/" am Zeilenanfang listet die Befehle, abgeschaltete nicht.</summary>
    [Test]
    procedure ListsCommandsWithoutDisabled;
    /// <summary>Hinter "/ignore " die Regeln, die in der Zeile darunter treffen (#297).</summary>
    [Test]
    procedure IgnoreOffersRulesBelow;
    /// <summary>In einem Kommentar keine Befehle.</summary>
    [Test]
    procedure NothingInComment;
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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Slash;

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

function RulesBelow: TSlashRuleIdsFunc;
begin
  Result :=
    function(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean
    begin
      AIds := ['magic-number'];
      Result := ALine = cCodeLine + 1;
    end;
end;

procedure TCompletionSlashTests.ListsCommandsWithoutDisabled;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('/');
  try
    Assert.IsTrue(TCompletionSlash.SlashItems(mRequest, nil, nil, mItems));
    Assert.IsTrue(MatchText('uses', Names(mItems)));
    Assert.IsTrue(MatchText('ignore', Names(mItems)));
    Assert.IsTrue(TCompletionSlash.SlashItems(mRequest, ['uses'], nil, mItems));
    Assert.IsFalse(MatchText('uses', Names(mItems)));
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionSlashTests.IgnoreOffersRulesBelow;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('/ignore ');
  try
    Assert.IsTrue(TCompletionSlash.SlashItems(mRequest, nil, RulesBelow(), mItems));
    Assert.AreEqual('magic-number', string.Join(',', Names(mItems)));
    Assert.AreEqual('/ignore', mItems.Items[0].Detail);
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionSlashTests.NothingInComment;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('// /');
  try
    Assert.IsFalse(TCompletionSlash.SlashItems(mRequest, nil, nil, mItems));
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionSlashTests.DirectiveNamesWithText;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mFound: Boolean;
begin
  mRequest := RequestFor('{$DEFI');
  try
    Assert.IsTrue(TCompletionSlash.DirectiveItems(mRequest, mItems));
    mFound := False;
    for mItem in mItems.Items do
    begin
      if mItem.Name = 'DEFINE' then
      begin
        mFound := True;
        Assert.IsTrue(mItem.Detail <> '', 'Beschreibung');
      end;
    end;
    Assert.IsTrue(mFound, string.Join(',', Names(mItems)));
  finally
    mRequest.Free;
  end;
  mRequest := RequestFor('Wert := 1;');
  try
    Assert.IsFalse(TCompletionSlash.DirectiveItems(mRequest, mItems));
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionSlashTests.SymbolsAfterIfdef;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
  mContext: TConditionalContext;
begin
  mContext := Default(TConditionalContext);
  mContext.CompletionEnabled := True;
  mRequest := RequestFor('{$IFDEF ');
  try
    Assert.IsTrue(TCompletionSlash.SymbolItems(mRequest, mContext, mItems));
    Assert.IsTrue(MatchText('MSWINDOWS', Names(mItems)), string.Join(',', Names(mItems)));
    mContext.CompletionEnabled := False;
    Assert.IsTrue(TCompletionSlash.SymbolItems(mRequest, mContext, mItems));
    Assert.AreEqual(0, Integer(Length(mItems.Items)), 'abgeschaltet');
  finally
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionSlashTests);

end.
