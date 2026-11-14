unit Atlas.Core.Forms.Tests;

// Tests für Formulartext und Formularänderungen aus dem Designer (#402).

interface

uses
  System.Classes,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFormsTests = class
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure WritesComponentsAndHandlers;
    [Test]
    procedure FindsRenamedHandlers;
    [Test]
    procedure RejectsOtherChanges;
    [Test]
    procedure ReadsObjectNames;
    [Test]
    procedure FindsPropertyChanges;
    [Test]
    procedure ReadsStringValues;
  end;

  /// <summary>Wurzel wie ein Datenmodul: schreibt die eigenen Komponenten mit.</summary>
  TTestRoot = class(TComponent)
  protected
    procedure GetChildren(Proc: TGetChildProc; Root: TComponent); override;
  end;

  TTestPing = class(TComponent)
  private
    FOnPing: TNotifyEvent;
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
    property OnPing: TNotifyEvent read FOnPing write FOnPing;
  end;

  TTestHandler = class
  public
    procedure Ping(Sender: TObject);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Forms.Text,
  Atlas.Core.Forms.Changes;

{ TTestRoot }

procedure TTestRoot.GetChildren(Proc: TGetChildProc; Root: TComponent);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ComponentCount - 1 do
  begin
    Proc(Components[mIndex]);
  end;
end;

{ TTestHandler }

procedure TTestHandler.Ping(Sender: TObject);
begin
  // Nur als Ziel des Ereignisses gebraucht; die Tests prüfen, dass es zugewiesen ist.
end;

const
  cForm =
    'object Form1: TForm1'#13#10 +
    '  Caption = ''Kunden'''#13#10 +
    '  OnCreate = FormCreate'#13#10 +
    '  object Panel1: TPanel'#13#10 +
    '    object Button1: TButton'#13#10 +
    '      Caption = ''OK'''#13#10 +
    '      OnClick = Button1Click'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object Grid: TDBGrid'#13#10 +
    '    Columns = <'#13#10 +
    '      item'#13#10 +
    '        FieldName = ''Name'''#13#10 +
    '      end>'#13#10 +
    '    OnDblClick = GridDblClick'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

procedure TAtlasFormsTests.WarmUpFirstUse;
begin
  WritesComponentsAndHandlers;
end;

procedure TAtlasFormsTests.WritesComponentsAndHandlers;
var
  mRoot: TTestRoot;
  mPing: TTestPing;
  mHandler: TTestHandler;
  mText: string;
begin
  mRoot := TTestRoot.Create(nil);
  mHandler := TTestHandler.Create;
  try
    mRoot.Name := 'Form1';
    mPing := TTestPing.Create(mRoot);
    mPing.Name := 'Ping1';
    mPing.Caption := 'Hallo';
    mPing.OnPing := mHandler.Ping;
    mText := TAtlasFormText.Write(mRoot,
      function(AMethod: TMethod): string
      begin
        // Im Designer weiß das der Designer; hier reicht ein fester Name.
        if AMethod.Data = Pointer(mHandler) then
        begin
          Result := 'Ping1Ping';
        end
        else
        begin
          Result := '';
        end;
      end);
  finally
    mHandler.Free;
    mRoot.Free;
  end;
  Assert.Contains(mText, 'object Form1: TTestRoot');
  Assert.Contains(mText, 'object Ping1: TTestPing');
  Assert.Contains(mText, 'Caption = ''Hallo''');
  Assert.Contains(mText, 'OnPing = Ping1Ping');
end;

procedure TAtlasFormsTests.FindsRenamedHandlers;
var
  mChanges: TArray<TAtlasFormEventChange>;
  mReason: string;
begin
  Assert.IsTrue(TAtlasFormChanges.Diff(cForm, cForm.Replace('OnClick = Button1Click', 'OnClick = SaveClick')
    .Replace('OnCreate = FormCreate', 'OnCreate = Startup').Replace('OnDblClick = GridDblClick',
    'OnDblClick = OpenCustomer'), mChanges, mReason), mReason);
  Assert.AreEqual(3, Integer(Length(mChanges)));
  Assert.AreEqual('', mChanges[0].Component, 'das Formular selbst');
  Assert.AreEqual('OnCreate', mChanges[0].EventName);
  Assert.AreEqual('Startup', mChanges[0].NewHandler);
  Assert.AreEqual('Button1', mChanges[1].Component, 'verschachtelt im Panel');
  Assert.AreEqual('Button1Click', mChanges[1].OldHandler);
  Assert.AreEqual('SaveClick', mChanges[1].NewHandler);
  Assert.AreEqual('Grid', mChanges[2].Component, 'nach einer Kollektion');
  Assert.IsTrue(TAtlasFormChanges.Diff(cForm, cForm, mChanges, mReason));
  Assert.AreEqual(0, Integer(Length(mChanges)), 'unverändert');
end;

procedure TAtlasFormsTests.RejectsOtherChanges;
var
  mChanges: TArray<TAtlasFormEventChange>;
  mReason: string;
begin
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('object Button1: TButton', 'object Save: TButton'),
    mChanges, mReason), 'Komponente umbenannt');
  Assert.Contains(mReason, 'Zeile 5');
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('''OK''', '''Speichern'''), mChanges, mReason),
    'andere Eigenschaft');
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('    end'#13#10'  end', '    end'#13#10'  end'#13#10),
    mChanges, mReason), 'Zeile hinzugefügt');
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('OnClick = Button1Click', 'OnPress = Button1Click'),
    mChanges, mReason), 'anderes Ereignis');
end;

procedure TAtlasFormsTests.FindsPropertyChanges;
var
  mChanges: TArray<TAtlasFormEventChange>;
  mProperties: TArray<TAtlasFormPropertyChange>;
  mReason: string;
begin
  // Eigenschaftsregeln (#309): geänderter Wert, eingefügte Zeile; Ereignisse wie bisher.
  Assert.IsTrue(TAtlasFormChanges.Diff(cForm, cForm.Replace('''OK''', '''Speichern''')
    .Replace('    object Button1: TButton'#13#10, '    object Button1: TButton'#13#10'      Default = True'#13#10)
    .Replace('OnCreate = FormCreate', 'OnCreate = Startup'), mChanges, mProperties, mReason), mReason);
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.AreEqual(2, Integer(Length(mProperties)));
  Assert.AreEqual('Button1', mProperties[0].Component);
  Assert.AreEqual('Default', mProperties[0].PropertyPath);
  Assert.AreEqual('True', mProperties[0].Value);
  Assert.IsFalse(mProperties[0].Removed);
  Assert.AreEqual('Caption', mProperties[1].PropertyPath);
  Assert.AreEqual('''Speichern''', mProperties[1].Value);
  // Entfernte Zeile (Rückgängig): zurück zum Vorgabewert.
  Assert.IsTrue(TAtlasFormChanges.Diff(cForm, cForm.Replace('  Caption = ''Kunden'''#13#10, ''), mChanges, mProperties,
    mReason), mReason);
  Assert.AreEqual(1, Integer(Length(mProperties)));
  Assert.AreEqual('', mProperties[0].Component, 'das Formular selbst');
  Assert.IsTrue(mProperties[0].Removed);
  // Verschachtelte Pfade zählen, Kollektionseinträge und neue Objekte nicht.
  Assert.IsTrue(TAtlasFormChanges.Diff(cForm, cForm.Replace('  Caption = ''Kunden'''#13#10,
    '  Caption = ''Kunden'''#13#10'  Font.Name = ''Segoe UI'''#13#10), mChanges, mProperties, mReason), mReason);
  Assert.AreEqual('Font.Name', mProperties[0].PropertyPath);
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('''Name''', '''Vorname'''), mChanges, mProperties, mReason),
    'Kollektionseintrag');
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('  object Grid: TDBGrid'#13#10,
    '  object Neu: TButton'#13#10'  end'#13#10'  object Grid: TDBGrid'#13#10), mChanges, mProperties, mReason),
    'neues Objekt');
  // Die alte Überladung bleibt bei Ereignissen.
  Assert.IsFalse(TAtlasFormChanges.Diff(cForm, cForm.Replace('''OK''', '''Speichern'''), mChanges, mReason));
end;

procedure TAtlasFormsTests.ReadsStringValues;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasFormChanges.StringValue('''Segoe UI''', mText));
  Assert.AreEqual('Segoe UI', mText);
  Assert.IsTrue(TAtlasFormChanges.StringValue('''It''''s''', mText));
  Assert.AreEqual('It''s', mText);
  Assert.IsTrue(TAtlasFormChanges.StringValue('''Gr''#252''n''', mText));
  Assert.AreEqual('Gr' + Char(252) + 'n', mText);
  Assert.IsFalse(TAtlasFormChanges.StringValue('True', mText));
end;

procedure TAtlasFormsTests.ReadsObjectNames;
var
  mIsObject: Boolean;
begin
  Assert.AreEqual('Button1', TAtlasFormChanges.ObjectName('    object Button1: TButton', mIsObject));
  Assert.IsTrue(mIsObject);
  Assert.AreEqual('Form2', TAtlasFormChanges.ObjectName('inherited Form2: TForm2', mIsObject));
  Assert.AreEqual('Frame1', TAtlasFormChanges.ObjectName('  inline Frame1: TFrame1 [0]', mIsObject));
  Assert.AreEqual('', TAtlasFormChanges.ObjectName('  object TTimer', mIsObject));
  Assert.IsTrue(mIsObject, 'ohne Namen');
  Assert.AreEqual('', TAtlasFormChanges.ObjectName('  ObjectName = ''x''', mIsObject));
  Assert.IsFalse(mIsObject);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormsTests);

end.
