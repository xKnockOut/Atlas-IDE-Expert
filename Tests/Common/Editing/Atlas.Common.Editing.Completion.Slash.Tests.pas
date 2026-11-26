unit Atlas.Common.Editing.Completion.Slash.Tests;

// Tests für die Vervollständigung der Schnellbefehle nach "/" (#293 ff.).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingSlashCompletionTests = class
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
    /// <summary>Ohne Auskunft der Zeile darunter die Kennungen des Katalogs.</summary>
    [Test]
    procedure IgnoreFallsBackToCatalog;
    /// <summary>Die Quelle antwortet allein; sind alle Befehle aus, geht es weiter.</summary>
    [Test]
    procedure SourceAnswersAlone;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Answer,
  Atlas.Common.Editing.Completion.Slash;

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

{ TEditingSlashCompletionTests }

procedure TEditingSlashCompletionTests.ListsCommandsWithoutDisabled;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('/');
  try
    Assert.IsTrue(TEditingSlashCompletion.Items(mRequest, nil, nil, nil, mItems));
    Assert.IsTrue(MatchText('uses', Names(mItems)));
    Assert.IsTrue(MatchText('ignore', Names(mItems)));
    Assert.IsTrue(TEditingSlashCompletion.Items(mRequest, ['uses'], nil, nil, mItems));
    Assert.IsFalse(MatchText('uses', Names(mItems)));
  finally
    mRequest.Free;
  end;
end;

procedure TEditingSlashCompletionTests.IgnoreOffersRulesBelow;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('/ignore ');
  try
    Assert.IsTrue(TEditingSlashCompletion.Items(mRequest, nil, RulesBelow(), nil, mItems));
    Assert.AreEqual('magic-number', string.Join(',', Names(mItems)));
    Assert.AreEqual('/ignore', mItems.Items[0].Detail);
  finally
    mRequest.Free;
  end;
end;

procedure TEditingSlashCompletionTests.NothingInComment;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('// /');
  try
    Assert.IsFalse(TEditingSlashCompletion.Items(mRequest, nil, nil, nil, mItems));
  finally
    mRequest.Free;
  end;
end;

procedure TEditingSlashCompletionTests.IgnoreFallsBackToCatalog;
var
  mRequest: TCompletionRequest;
  mItems: TCompletionItems;
begin
  mRequest := RequestFor('/ignore ');
  try
    Assert.IsTrue(TEditingSlashCompletion.Items(mRequest, nil, nil,
      function: TArray<string>
      begin
        Result := ['empty-block'];
      end, mItems));
    Assert.AreEqual('empty-block', string.Join(',', Names(mItems)));
  finally
    mRequest.Free;
  end;
end;

procedure TEditingSlashCompletionTests.SourceAnswersAlone;
var
  mRequest: TCompletionRequest;
  mAnswer: TCompletionAnswer;
  mSource: TCompletionSource;
begin
  mRequest := RequestFor('/');
  mAnswer := TCompletionAnswer.Create;
  try
    mSource := TEditingSlashCompletion.Source(nil, nil, nil);
    Assert.AreEqual(Ord(TCompletionOutcome.Answered), Ord(mSource(mRequest, mAnswer)));
    Assert.IsTrue(MatchText('uses', Names(mAnswer.Exclusive)));
    mSource := TEditingSlashCompletion.Source(
      function(const AUri: string; out ADisabled: TArray<string>): Boolean
      begin
        ADisabled := nil;
        Result := False;
      end, nil, nil);
    Assert.AreEqual(Ord(TCompletionOutcome.Next), Ord(mSource(mRequest, mAnswer)));
  finally
    mAnswer.Free;
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingSlashCompletionTests);

end.
