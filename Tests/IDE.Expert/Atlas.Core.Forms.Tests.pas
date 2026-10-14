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
    [Test]
    procedure WritesComponentsAndHandlers;
    [Test]
    procedure FindsRenamedHandlers;
    [Test]
    procedure RejectsOtherChanges;
    [Test]
    procedure ReadsObjectNames;
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
  Index: Integer;
begin
  for Index := 0 to ComponentCount - 1 do
    Proc(Components[Index]);
end;

{ TTestHandler }

procedure TTestHandler.Ping(Sender: TObject);
begin
end;

const
  Form =
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

procedure TAtlasFormsTests.WritesComponentsAndHandlers;
var
  Root: TTestRoot;
  Ping: TTestPing;
  Handler: TTestHandler;
  Text: string;
begin
  Root := TTestRoot.Create(nil);
  Handler := TTestHandler.Create;
  try
    Root.Name := 'Form1';
    Ping := TTestPing.Create(Root);
    Ping.Name := 'Ping1';
    Ping.Caption := 'Hallo';
    Ping.OnPing := Handler.Ping;
    Text := TAtlasFormText.Write(Root,
      function(AMethod: TMethod): string
      begin
        // Im Designer weiß das der Designer; hier reicht ein fester Name.
        if AMethod.Data = Pointer(Handler) then
          Result := 'Ping1Ping'
        else
          Result := '';
      end);
  finally
    Handler.Free;
    Root.Free;
  end;
  Assert.Contains(Text, 'object Form1: TTestRoot');
  Assert.Contains(Text, 'object Ping1: TTestPing');
  Assert.Contains(Text, 'Caption = ''Hallo''');
  Assert.Contains(Text, 'OnPing = Ping1Ping');
end;

procedure TAtlasFormsTests.FindsRenamedHandlers;
var
  Changes: TArray<TAtlasFormEventChange>;
  Reason: string;
begin
  Assert.IsTrue(TAtlasFormChanges.Diff(Form, Form.Replace('OnClick = Button1Click', 'OnClick = SaveClick')
    .Replace('OnCreate = FormCreate', 'OnCreate = Startup').Replace('OnDblClick = GridDblClick',
    'OnDblClick = OpenCustomer'), Changes, Reason), Reason);
  Assert.AreEqual(3, Integer(Length(Changes)));
  Assert.AreEqual('', Changes[0].Component, 'das Formular selbst');
  Assert.AreEqual('OnCreate', Changes[0].EventName);
  Assert.AreEqual('Startup', Changes[0].NewHandler);
  Assert.AreEqual('Button1', Changes[1].Component, 'verschachtelt im Panel');
  Assert.AreEqual('Button1Click', Changes[1].OldHandler);
  Assert.AreEqual('SaveClick', Changes[1].NewHandler);
  Assert.AreEqual('Grid', Changes[2].Component, 'nach einer Kollektion');
  Assert.IsTrue(TAtlasFormChanges.Diff(Form, Form, Changes, Reason));
  Assert.AreEqual(0, Integer(Length(Changes)), 'unverändert');
end;

procedure TAtlasFormsTests.RejectsOtherChanges;
var
  Changes: TArray<TAtlasFormEventChange>;
  Reason: string;
begin
  Assert.IsFalse(TAtlasFormChanges.Diff(Form, Form.Replace('object Button1: TButton', 'object Save: TButton'),
    Changes, Reason), 'Komponente umbenannt');
  Assert.Contains(Reason, 'Zeile 5');
  Assert.IsFalse(TAtlasFormChanges.Diff(Form, Form.Replace('''OK''', '''Speichern'''), Changes, Reason),
    'andere Eigenschaft');
  Assert.IsFalse(TAtlasFormChanges.Diff(Form, Form.Replace('    end'#13#10'  end', '    end'#13#10'  end'#13#10),
    Changes, Reason), 'Zeile hinzugefügt');
  Assert.IsFalse(TAtlasFormChanges.Diff(Form, Form.Replace('OnClick = Button1Click', 'OnPress = Button1Click'),
    Changes, Reason), 'anderes Ereignis');
end;

procedure TAtlasFormsTests.ReadsObjectNames;
var
  IsObject: Boolean;
begin
  Assert.AreEqual('Button1', TAtlasFormChanges.ObjectName('    object Button1: TButton', IsObject));
  Assert.IsTrue(IsObject);
  Assert.AreEqual('Form2', TAtlasFormChanges.ObjectName('inherited Form2: TForm2', IsObject));
  Assert.AreEqual('Frame1', TAtlasFormChanges.ObjectName('  inline Frame1: TFrame1 [0]', IsObject));
  Assert.AreEqual('', TAtlasFormChanges.ObjectName('  object TTimer', IsObject));
  Assert.IsTrue(IsObject, 'ohne Namen');
  Assert.AreEqual('', TAtlasFormChanges.ObjectName('  ObjectName = ''x''', IsObject));
  Assert.IsFalse(IsObject);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormsTests);

end.
