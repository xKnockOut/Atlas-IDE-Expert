unit Atlas.Common.Mcp.IdeContext.Tests;

// Tests für get_ide_context (#2050): Argumente, Auswahl der IDE (gewählt oder jüngster Stand), Text mit den
// Abschnitten aus include, JSON, Antwort ohne IDE bzw. ohne Stand, Texte in beiden Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIdeContextTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ArgumentsAndDefaults;
    [Test]
    procedure PicksChosenOrNewestIde;
    [Test]
    procedure TextShowsWhereTheDeveloperIs;
    [Test]
    procedure IncludeLimitsSections;
    [Test]
    procedure SelectionWithoutText;
    [Test]
    procedure JsonReport;
    [Test]
    procedure WithoutIdeOrState;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Mcp.Server,
  Atlas.Text.IdeContext,
  Atlas.Common.Mcp.IdeContext;

function Now_: TDateTime;
begin
  Result := EncodeDateTime(2026, 11, 18, 21, 30, 4, 0);
end;

function Sample: TIdeContext;
var
  mMessage: TIdeContextMessage;
begin
  Result := Default(TIdeContext);
  Result.Pid := 14328;
  Result.AtUtc := EncodeDateTime(2026, 11, 18, 21, 30, 0, 0);
  Result.AtLocal := Result.AtUtc;
  Result.Editor.Known := True;
  Result.Editor.FileName := 'C:\Quellen\Checklist.pas';
  Result.Editor.Line := 118;
  Result.Editor.Column := 3;
  Result.Editor.Modified := True;
  Result.Editor.Method := 'TChecklist.Toggle';
  Result.Selection.Known := True;
  Result.Selection.StartLine := 121;
  Result.Selection.StartColumn := 1;
  Result.Selection.EndLine := 122;
  Result.Selection.EndColumn := 14;
  Result.Selection.Length := 40;
  Result.Selection.Text := 'mLine := LineAt(AText);'#13#10'Exit(False);';
  Result.Project.FileName := 'C:\Quellen\Tracker.dproj';
  Result.Project.Configuration := 'Debug';
  Result.Project.Platform := 'Win64';
  Result.Build.Known := True;
  Result.Build.Kind := 'check';
  Result.Build.Success := True;
  Result.Build.Warnings := 2;
  Result.Build.FinishedAtUtc := EncodeDateTime(2026, 11, 18, 21, 28, 0, 0);
  mMessage := Default(TIdeContextMessage);
  mMessage.FileName := 'C:\Quellen\Checklist.pas';
  mMessage.Line := 127;
  mMessage.Severity := 'warning';
  mMessage.Code := 'W1036';
  mMessage.Text := 'Variable ''mMark'' ist möglicherweise nicht initialisiert';
  Result.Build.Messages := [mMessage];
  Result.Tabs := ['C:\Quellen\Checklist.pas', 'C:\Quellen\Board.pas'];
end;

/// <summary>Abschnitte als Folge ihrer Ordnungszahlen, damit ein Fehlschlag beide Mengen zeigt.</summary>
function PartsText(const AParts: TMcpIdeContextParts): string;
var
  mPart: TMcpIdeContextPart;
begin
  Result := '';
  for mPart in AParts do
  begin
    Result := Result + IntToStr(Ord(mPart)) + ' ';
  end;
end;

function RequestOf(const AJson: string): TMcpIdeContextRequest;
var
  mArguments: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Result := TMcpIdeContextRequest.FromArguments(mArguments);
  finally
    mArguments.Free;
  end;
end;

{ TMcpIdeContextTests }

procedure TMcpIdeContextTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpIdeContextTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpIdeContextTests.ArgumentsAndDefaults;
var
  mRequest: TMcpIdeContextRequest;
begin
  mRequest := TMcpIdeContextRequest.FromArguments(nil);
  Assert.AreEqual(PartsText([TMcpIdeContextPart.Editor, TMcpIdeContextPart.Selection, TMcpIdeContextPart.Project,
    TMcpIdeContextPart.Build, TMcpIdeContextPart.Tabs]), PartsText(mRequest.Parts), 'alle Abschnitte');
  Assert.AreEqual(Int64(0), Int64(mRequest.Ide));
  Assert.IsFalse(mRequest.AsJson);
  mRequest := RequestOf('{"include":["EDITOR","build"],"ide":42,"format":"json"}');
  Assert.AreEqual(PartsText([TMcpIdeContextPart.Editor, TMcpIdeContextPart.Build]), PartsText(mRequest.Parts));
  Assert.AreEqual(Int64(42), Int64(mRequest.Ide));
  Assert.IsTrue(mRequest.AsJson);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"include":["cursor"]}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"ide":0}');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      RequestOf('{"format":"xml"}');
    end, EMcpToolError);
end;

procedure TMcpIdeContextTests.PicksChosenOrNewestIde;
var
  mOlder, mNewer: TIdeContext;
  mReason: string;
begin
  mOlder := Sample;
  mOlder.Pid := 10;
  mNewer := Sample;
  mNewer.Pid := 20;
  mNewer.AtUtc := mOlder.AtUtc + OneSecond;
  Assert.AreEqual(1, TMcpIdeContext.Pick([mOlder, mNewer], 0, mReason), 'jüngster Stand');
  Assert.AreEqual(0, TMcpIdeContext.Pick([mOlder, mNewer], 10, mReason), 'gewählte IDE');
  Assert.AreEqual(-1, TMcpIdeContext.Pick([mOlder, mNewer], 30, mReason));
  Assert.IsTrue(mReason.Contains('10, 20'), mReason);
end;

procedure TMcpIdeContextTests.TextShowsWhereTheDeveloperIs;
var
  mText: string;
begin
  mText := TMcpIdeContext.Report(Sample, TMcpIdeContextRequest.FromArguments(nil), Now_);
  Assert.IsTrue(mText.Contains('IDE 14328 · Stand vor 4 s'), mText);
  Assert.IsTrue(mText.Contains('C:\Quellen\Checklist.pas:118:3  (ungespeichert)'), mText);
  Assert.IsTrue(mText.Contains('Methode    TChecklist.Toggle'), mText);
  Assert.IsTrue(mText.Contains('Z. 121:1–122:14 (40 Zeichen)'), mText);
  Assert.IsTrue(mText.Contains('           Exit(False);'), mText);
  Assert.IsTrue(mText.Contains('C:\Quellen\Tracker.dproj · Debug · Win64'), mText);
  Assert.IsTrue(mText.Contains('vor 2 Min. · check · 0 Fehler, 2 Warnungen, 0 Hinweise · erfolgreich'), mText);
  Assert.IsTrue(mText.Contains('W1036 '), mText);
  Assert.IsTrue(mText.Contains(':127  Variable'), mText);
  Assert.IsTrue(mText.Contains('Reiter'), mText);
end;

procedure TMcpIdeContextTests.IncludeLimitsSections;
var
  mText: string;
begin
  mText := TMcpIdeContext.Report(Sample, RequestOf('{"include":["project"]}'), Now_);
  Assert.IsTrue(mText.Contains('Tracker.dproj'), mText);
  Assert.IsFalse(mText.Contains('TChecklist.Toggle'), mText);
  Assert.IsFalse(mText.Contains('W1036'), mText);
end;

procedure TMcpIdeContextTests.SelectionWithoutText;
var
  mContext: TIdeContext;
  mText: string;
begin
  mContext := Sample;
  mContext.Selection.Text := '';
  mContext.Selection.TextOmitted := True;
  mText := TMcpIdeContext.Report(mContext, RequestOf('{"include":["selection"]}'), Now_);
  Assert.IsTrue(mText.Contains('assistants.context.selection'), mText);
  mContext := Sample;
  mContext.Selection.Truncated := True;
  mText := TMcpIdeContext.Report(mContext, RequestOf('{"include":["selection"]}'), Now_);
  Assert.IsTrue(mText.Contains('gekürzt auf'), mText);
end;

procedure TMcpIdeContextTests.JsonReport;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.ParseJSONValue(TMcpIdeContext.Report(Sample, RequestOf(
    '{"include":["editor","tabs"],"format":"json"}'), Now_)) as TJSONObject;
  try
    Assert.IsNotNull(mRoot);
    Assert.AreEqual(14328, mRoot.GetValue<Integer>('pid'));
    Assert.AreEqual(4, mRoot.GetValue<Integer>('ageSeconds'));
    Assert.AreEqual('TChecklist.Toggle', mRoot.GetValue<string>('editor.method'));
    Assert.AreEqual(2, Integer(mRoot.GetValue<TJSONArray>('tabs').Count));
    Assert.IsNull(mRoot.GetValue('build'), 'nicht in include');
    Assert.IsNull(mRoot.GetValue('selection'));
    Assert.IsNull(mRoot.GetValue('format'));
  finally
    mRoot.Free;
  end;
end;

procedure TMcpIdeContextTests.WithoutIdeOrState;
begin
  Assert.AreEqual('Keine IDE mit Atlas-Plugin gefunden.', TMcpIdeContext.NoContext(nil));
  Assert.IsTrue(TMcpIdeContext.NoContext([7, 9]).Contains('7, 9'));
  Assert.IsTrue(TMcpIdeContext.NoContext([7]).Contains('assistants.context'));
end;

procedure TMcpIdeContextTests.EnglishTexts;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  mText := TMcpIdeContext.Report(Sample, TMcpIdeContextRequest.FromArguments(nil), Now_);
  Assert.IsTrue(mText.Contains('state 4 s ago'), mText);
  Assert.IsTrue(mText.Contains('(unsaved)'), mText);
  Assert.IsTrue(mText.Contains('0 errors, 2 warnings, 0 hints · succeeded'), mText);
  Assert.AreEqual('No IDE with the Atlas plugin found.', TMcpIdeContext.NoContext(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeContextTests);

end.
