unit Atlas.Common.Mcp.CompilerMessageTools.Tests;

// Tests für das MCP-Werkzeug explain_compiler_message (#2621): Parameter, Einzel- und Mehrfachaufruf, Sprachen,
// unbekannte Nummer, sichere Korrektur als Diff, unsichere als Text, Folgefehler und der Hinweis in build_project.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TMcpCompilerMessageToolsTests = class
  private
    FLanguage: TTextLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsSingleMessageAndArray;
    [Test]
    procedure WithoutMessageIsAnError;
    [Test]
    procedure WithoutFileOnlyGeneralExplanation;
    [Test]
    procedure SafePitfallFixComesAsDiff;
    [Test]
    procedure MissingUnitComesAsDiff;
    [Test]
    procedure CompilerFixComesAsDiff;
    [Test]
    procedure UnsafeFixComesAsText;
    [Test]
    procedure MarksFollowUpErrors;
    [Test]
    procedure UnknownCodeLinksDocWiki;
    [Test]
    procedure FindsShiftedLine;
    [Test]
    procedure JsonHasTheSameFields;
    [Test]
    procedure AnswersInGerman;
    [Test]
    procedure BuildReportPointsToTheTool;
  end;

implementation

uses
  System.SysUtils,
  // Inline-Funktionen von TJSONArray und TJSONObject (H2443).
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.CompilerMessageTools;

const
  cFile = 'Source/Ref.Daten.pas';
  // Getrennt geschrieben, weil der Linux-Bau System.TMonitor im Quelltext zu TMonitor macht (Convert-ForFpc.py).
  cQualified = 'System' + '.TMonitor.';

  cUnit = 'unit Ref.Daten;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  System.SysUtils;'#13#10#13#10 +
    'implementation'#13#10#13#10'procedure Warte;'#13#10'begin'#13#10'  TMonitor.Enter(FLock);'#13#10 +
    '  mStart := GetTickCount64;'#13#10'end;'#13#10#13#10'end.'#13#10;

  cTwins = 'unit Ref.Filter;'#13#10#13#10'interface'#13#10#13#10'type'#13#10 +
    '  TAtlasNameFilter = reference to function(const AName: string): Boolean;'#13#10 +
    '  TAtlasNamePredicate = reference to function(const AName: string): Boolean;'#13#10#13#10'implementation'#13#10 +
    #13#10'procedure Setze;'#13#10'begin'#13#10'  FFilter := FPredicate;'#13#10'end;'#13#10#13#10'end.'#13#10;

/// <summary>Liest nur cFile mit dem Inhalt AText.</summary>
function ReaderOf(const AText: string): TMcpReadText;
begin
  Result :=
    function(const AFileName: string; out AContent: string): Boolean
    begin
      Result := AFileName = cFile;
      AContent := '';
      if Result then
      begin
        AContent := AText;
      end;
    end;
end;

function Message(const ACode, AText: string; ALine: Integer): TMcpCompilerMessage;
begin
  Result := Default(TMcpCompilerMessage);
  Result.Code := ACode;
  Result.Text := AText;
  Result.FileName := cFile;
  Result.Line := ALine;
end;

function Explain(const AMessages: TArray<TMcpCompilerMessage>; const AText: string; AJson: Boolean): string;
var
  mRequest: TMcpExplainRequest;
begin
  mRequest := Default(TMcpExplainRequest);
  mRequest.Messages := AMessages;
  mRequest.Json := AJson;
  mRequest.ReadText := ReaderOf(AText);
  Result := TMcpCompilerMessageTools.Explain(mRequest);
end;

function Occurrences(const AText, APart: string): Integer;
var
  mStart: Integer;
begin
  Result := 0;
  mStart := Pos(APart, AText);
  while mStart > 0 do
  begin
    Inc(Result);
    mStart := Pos(APart, AText, mStart + 1);
  end;
end;

function Contains(const AText, APart: string): Boolean;
begin
  Result := Pos(APart, AText) > 0;
end;

{ TMcpCompilerMessageToolsTests }

procedure TMcpCompilerMessageToolsTests.Setup;
begin
  FLanguage := TAtlasLocale.Language;
  TAtlasLocale.Use(TTextLanguage.English);
end;

procedure TMcpCompilerMessageToolsTests.TearDown;
begin
  TAtlasLocale.Use(FLanguage);
end;

procedure TMcpCompilerMessageToolsTests.ReadsSingleMessageAndArray;
var
  mArguments: TJSONObject;
  mMessages: TArray<TMcpCompilerMessage>;
begin
  mArguments := TJSONObject.ParseJSONValue('{"message":"[dcc32 Fehler] E2003 Undeklarierter Bezeichner: ''X''",' +
    '"file":"a.pas","line":3,"column":7}') as TJSONObject;
  try
    mMessages := TMcpCompilerMessageTools.MessagesOf(mArguments);
  finally
    mArguments.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mMessages)));
  Assert.AreEqual('E2003', mMessages[0].Code);
  Assert.AreEqual('a.pas', mMessages[0].FileName);
  Assert.AreEqual(3, mMessages[0].Line);
  Assert.AreEqual(7, mMessages[0].Column);
  mArguments := TJSONObject.ParseJSONValue('{"messages":[{"code":"e2010","text":"a"},{"code":"W1036"},7]}') as
    TJSONObject;
  try
    mMessages := TMcpCompilerMessageTools.MessagesOf(mArguments);
  finally
    mArguments.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mMessages)));
  Assert.AreEqual('E2010', mMessages[0].Code);
  Assert.AreEqual('a', mMessages[0].Text);
  Assert.AreEqual('W1036', mMessages[1].Code);
  mMessages := nil;
end;

procedure TMcpCompilerMessageToolsTests.WithoutMessageIsAnError;
var
  mArguments: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue('{"file":"a.pas"}') as TJSONObject;
  try
    Assert.WillRaise(
      procedure
      begin
        TMcpCompilerMessageTools.MessagesOf(mArguments);
      end, EMcpToolError);
  finally
    mArguments.Free;
  end;
end;

procedure TMcpCompilerMessageToolsTests.WithoutFileOnlyGeneralExplanation;
var
  mText: string;
  mMessage: TMcpCompilerMessage;
begin
  mMessage := Message('E2010', 'Incompatible types: ''Integer'' and ''string''', 0);
  mMessage.FileName := '';
  mText := Explain([mMessage], '', False);
  Assert.IsTrue(Contains(mText, '## E2010 – Incompatible types'), mText);
  Assert.IsTrue(Contains(mText, 'Other causes: Two method reference types of the same shape'), mText);
  Assert.IsTrue(Contains(mText, 'type-mismatch'), mText);
  Assert.IsTrue(Contains(mText, 'Right:'), mText);
  Assert.IsTrue(Contains(mText, 'docwiki.embarcadero.com'), mText);
  Assert.IsFalse(Contains(mText, 'Likely:'), mText);
  Assert.IsFalse(Contains(mText, '```diff'), mText);
end;

procedure TMcpCompilerMessageToolsTests.SafePitfallFixComesAsDiff;
var
  mText: string;
begin
  mText := Explain([Message('E2003', 'Undeclared identifier: ''Enter''', 12)], cUnit, False);
  Assert.IsTrue(Contains(mText, 'Likely: TMonitor from Vcl.Forms hides the one from System (TMonitor.)'), mText);
  Assert.IsTrue(Contains(mText, 'Fix (safe): Qualify TMonitor with the unit name System.'), mText);
  Assert.IsTrue(Contains(mText, '--- a/Source/Ref.Daten.pas'), mText);
  Assert.IsTrue(Contains(mText, '-  TMonitor.Enter(FLock);'), mText);
  Assert.IsTrue(Contains(mText, '+  ' + cQualified + 'Enter(FLock);'), mText);
end;

procedure TMcpCompilerMessageToolsTests.MissingUnitComesAsDiff;
var
  mText: string;
begin
  mText := Explain([Message('E2003', 'Undeclared identifier: ''GetTickCount64''', 13)], cUnit, False);
  Assert.IsTrue(Contains(mText, 'Likely: Winapi.Windows missing in uses'), mText);
  Assert.IsTrue(Contains(mText, '```diff'), mText);
  Assert.IsTrue(Contains(mText, 'Winapi.Windows'), mText);
  Assert.IsTrue(Contains(mText, 'Rule while typing: winapi-uses-missing'), mText);
end;

procedure TMcpCompilerMessageToolsTests.CompilerFixComesAsDiff;
var
  mText: string;
begin
  mText := Explain([Message('H2443', 'Inline function ''TJSONArray.Count'' has not been expanded because unit ' +
    '''System.Generics.Collections'' is not specified in USES list', 13)], cUnit, False);
  Assert.IsTrue(Contains(mText, 'Fix (safe):'), mText);
  Assert.IsTrue(Contains(mText, '+  System.Generics.Collections'), mText);
end;

procedure TMcpCompilerMessageToolsTests.UnsafeFixComesAsText;
var
  mText: string;
begin
  mText := Explain([Message('E2010', 'Inkompatible Typen: ''TAtlasNameFilter'' und ''TAtlasNamePredicate''', 13)],
    cTwins, False);
  Assert.IsTrue(Contains(mText, 'Likely: Two method reference types of the same shape (TAtlasNameFilter, ' +
    'TAtlasNamePredicate)'), mText);
  Assert.IsTrue(Contains(mText, 'Fix: Use one shared type'), mText);
  Assert.IsFalse(Contains(mText, '```diff'), mText);
end;

procedure TMcpCompilerMessageToolsTests.MarksFollowUpErrors;
var
  mText: string;
begin
  mText := Explain([Message('E2003', 'Undeclared identifier: ''Enter''', 12),
    Message('E2250', 'There is no overloaded version of ''GetTickCount64''', 13)], cUnit, False);
  Assert.IsTrue(Contains(mText, '## E2003'), mText);
  Assert.IsTrue(Contains(mText, '## E2250'), mText);
  Assert.IsTrue(Contains(mText, 'Follow-up error of E2003 further up'), mText);
end;

procedure TMcpCompilerMessageToolsTests.UnknownCodeLinksDocWiki;
var
  mText: string;
begin
  mText := Explain([Message('E9999', 'Something odd', 3)], cUnit, False);
  Assert.IsTrue(Contains(mText, 'Atlas knows no explanation for E9999'), mText);
  Assert.IsTrue(Contains(mText, 'search=E9999'), mText);
  Assert.IsFalse(TMcpCompilerMessageTools.Explains('E9999'));
  Assert.IsTrue(TMcpCompilerMessageTools.Explains('E2003'));
  // Nur im Fallenkatalog, nicht im allgemeinen Katalog.
  Assert.IsTrue(TMcpCompilerMessageTools.Explains('E2362'));
end;

procedure TMcpCompilerMessageToolsTests.FindsShiftedLine;
var
  mText: string;
begin
  // Seit dem Build sind zwei Zeilen dazugekommen: TMonitor steht jetzt in Zeile 12 statt 10.
  mText := Explain([Message('E2003', 'Undeclared identifier: ''Enter''', 10)], cUnit, False);
  Assert.IsTrue(Contains(mText, 'the place is now in line 12'), mText);
  Assert.IsTrue(Contains(mText, '+  ' + cQualified + 'Enter(FLock);'), mText);
end;

procedure TMcpCompilerMessageToolsTests.JsonHasTheSameFields;
var
  mValue: TJSONValue;
  mItem: TJSONObject;
  mPitfall: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(Explain([Message('E2003', 'Undeclared identifier: ''Enter''', 12)], cUnit,
    True));
  try
    mItem := (mValue as TJSONObject).GetValue<TJSONArray>('messages').Items[0] as TJSONObject;
    Assert.AreEqual('E2003', mItem.GetValue<string>('code'));
    Assert.IsTrue(mItem.GetValue<Boolean>('known'));
    Assert.AreEqual('Undeclared identifier', mItem.GetValue<string>('name'));
    mPitfall := mItem.GetValue<TJSONArray>('pitfalls').Items[0] as TJSONObject;
    Assert.AreEqual('hidden-monitor', mPitfall.GetValue<string>('id'));
    Assert.IsTrue(mPitfall.GetValue<Boolean>('marked'));
    Assert.AreEqual('TMonitor.', mPitfall.GetValue<string>('evidence'));
    Assert.IsTrue(Contains(mItem.GetValue<TJSONObject>('fix').GetValue<string>('diff'), '+  ' + cQualified));
    Assert.IsTrue(mItem.GetValue<TJSONObject>('fix').GetValue<Boolean>('safe'));
    Assert.IsTrue(Contains(mItem.GetValue<TJSONArray>('rules').ToJSON, 'unresolved-identifier'));
  finally
    mValue.Free;
  end;
end;

procedure TMcpCompilerMessageToolsTests.AnswersInGerman;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  mText := Explain([Message('E2003', 'Undeklarierter Bezeichner: ''Enter''', 12)], cUnit, False);
  Assert.IsTrue(Contains(mText, '## E2003 – Undeklarierter Bezeichner'), mText);
  Assert.IsTrue(Contains(mText, 'Wahrscheinlich: TMonitor aus Vcl.Forms verdeckt den aus System'), mText);
  Assert.IsTrue(Contains(mText, 'Korrektur (sicher): TMonitor mit dem Unit-Namen System qualifizieren.'), mText);
end;

procedure TMcpCompilerMessageToolsTests.BuildReportPointsToTheTool;
var
  mBuild: TIdeBuild;
  mMessage: TCompilerMessage;
  mText: string;
begin
  mBuild := Default(TIdeBuild);
  mBuild.Known := True;
  mMessage := Default(TCompilerMessage);
  mMessage.Code := 'E2003';
  mMessage.Text := 'Undeclared identifier: ''X''';
  mBuild.Messages := [mMessage];
  mMessage.Code := 'E9999';
  mBuild.Messages := mBuild.Messages + [mMessage];
  mText := TMcpBuildTools.Report(mBuild, '', '');
  // Nur E2003 kennt Atlas.
  Assert.AreEqual(1, Occurrences(mText, '"explain"'), mText);
  Assert.AreEqual(1, Occurrences(mText, 'explain_compiler_message'), mText);
  Assert.IsTrue(Pos('"explain"', mText) < Pos('E9999', mText), mText);
  mBuild := Default(TIdeBuild);
end;

end.
