import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_dialog.dart';
import 'package:paper_elements/paper_input.dart';
import 'package:paper_elements/paper_toast.dart';
import 'package:core_elements/core_drawer_panel.dart';
import 'package:browser_detect/browser_detect.dart';
import 'dart:html';
import 'dart:async';
import 'dart:js';


import 'package:inputzone/iz_register.dart';
import 'inputzone.dart';

@CustomTag('iz-app')
class IzApp extends PolymerElement {
  
  @observable int availableTempSpace = 0;
  @observable int availablePersSpace = 0;
  @observable int uiUsedTemp=0; // just used for ui binding
  @observable int uiUsedPers=0; // just used for ui bindin
  @observable bool narrowedDrawer=false;
  @observable bool browserSupportPnacl=window.navigator.mimeTypes.any((mimetype)=> mimetype.type == 'application/x-pnacl');
  @observable bool browserSupportFS = false;
  @observable bool forcePersistent = false;
  
  @published String inputExt="*/*";
  @published String pnaclbin="";
  @published String emscrbin="";
  @observable bool initialized = false;
  @observable var runtime = RUNTIMETYPE.EMSCR;
  @observable String t_e_l;
  @observable bool compliantBrowser = true;
  
  EmbedElement embed;
  JsObject pnaclProxy;
  
  InputElement input;
  
  Worker infoWorker;
  
  ObservableMap<int,FileTask> tasks = new ObservableMap<int,FileTask>();
  

  FS_PERS_STATUS fs_pers_status = FS_PERS_STATUS.CLOSED;
  
  @observable ObservableList<FileTask> tasksWaitingOutOfQuotaDialog = new ObservableList<FileTask>();
  PaperDialog _outOfQuotaDialog;
  
  Uri appUrl;
  Map<String,String> options = {};

  
  IzApp.created() : super.created(){ 
    iz_app = this;
    detectBrowser();
    if(currentBrowser== BROWSER.INTERNETEXPLORER || currentBrowser== BROWSER.OPERA)
    {
      emscrbin='';
      compliantBrowser=false;
    }
      
    appUrl = Uri.parse(window.location.href); 
    if(appUrl.hasFragment){
      appUrl.fragment.split(";").forEach((f){
        if(f!=""){
          var opt = f.split("=");
          if(opt.length==2)
            options.addAll({opt[0].toLowerCase():opt[1].toLowerCase()});
          else
            options.addAll({opt[0].toLowerCase():''});
        } 
      });
    }
    
    if(options.containsKey('compatibilitymode')){
       runtime = RUNTIMETYPE.EMSCR;
     }
     else if(browserSupportPnacl){
       runtime = RUNTIMETYPE.PNACL;
       browserSupportPnacl=true;
     }     
    
    if(currentBrowser == BROWSER.CHROME){
      browserSupportFS = true;
      window.navigator.temporaryStorage.requestQuota(40*1024*1024*1024, (int received_size) {
        availableTempSpace = received_size;
            }, (e) {
              availableTempSpace =0;
            });
      
      window.onBeforeUnload.listen((e){    
        if(tasks.values.any((f)=>!f.contentDeleted)){
          Html5FS.temp().then((fs)=>fs.root.getDirectory('/InputZone').then((e)=> e.removeRecursively()));
          Html5FS.pers().then((fs)=>fs.root.getDirectory('/InputZone').then((e)=> e.removeRecursively()));
          e.returnValue="\n\nWARNING!\n\n You didn't purge every tasks before leaving.\n Next time, pay attention...\n\n";
        }
      });
    }
    initConverter();
  }
  
  bool _ready_done=false;
  void ready(){
    if(_ready_done)
      return;
    _ready_done=true;
    this.children.add(new DivElement()..id='disqus_thread');
    document.body.append((document.createElement('script') as ScriptElement)
        ..type = 'text/javascript'
        ..async = true
        ..src = 'http://' + 'inputzone' + '.disqus.com/embed.js');
      
        
      _outOfQuotaDialog = $['outOfQuotaDialog'];
      tasksWaitingOutOfQuotaDialog.listChanges.listen((changes)=>
        changes.forEach((change){
          if(change.addedCount>0)
            if(!_outOfQuotaDialog.opened)
              _outOfQuotaDialog.toggle();
          if(change.removed.length>0)
            if(tasksWaitingOutOfQuotaDialog.length>0)
              _outOfQuotaDialog.toggle();
        })
      );
      
  }
  
  
   void initConverter(){
     if(!initialized && infoWorker==null && embed == null){
       if(runtime == RUNTIMETYPE.EMSCR){
         if(emscrbin==''){
           return;
         }
         infoWorker = new Worker(emscrbin);
               infoWorker.onMessage.first.then((MessageEvent e){
                 initialized=true;
                 infoWorker.onMessage.listen(onEMSCREstimatedOutputSizeReceived);
               });
               infoWorker.postMessage(new WorkerPostMessage("workerReady",0,[]));  
       } 
       else{
         embed= new EmbedElement()..type="application/x-pnacl"..src=pnaclbin..width='0'..height='0'..id='pnacl'..onLoad.listen((_){
           initialized=true;
               embed.on['message'].listen((s){
                 //print("new message:"+(s as MessageEvent).data.toString());
                 var msg = new TaskMessage.FromNACLMessage((s as MessageEvent).data.toString());
                 if(msg.id!=0){
                   tasks[msg.id].handleTaskMessage(msg);
                 }
               });
               pnaclProxy = new JsObject.fromBrowserObject(embed); 
             });
         this.shadowRoot.children.add(embed);
          }
     }
    
   }
   
   void clickFab(){
     if(input == null)
     {
       input = new InputElement(type:'file')
       ..id="input"
       ..attributes.addAll({'accept':inputExt})
       ..onChange.first.then((evt)=>handleFile(evt));
       document.body.append(input);
     }
     input.click();
   }
   

   void handleFile(Event e){
      var files = input.files;

          // Loop through the FileList and render image files as thumbnails.
          input.files.forEach((f) {
            newInput(f);
          });
          document.body.children.remove(input);
          input = null;
    }
   
   
   void newInput(File file){
     var url = Url.createObjectUrl(file);
     print(url);
     FileTask task;
     if(iz_app.runtime == RUNTIMETYPE.PNACL)
       task = new PNaclTask(file.name, url, file.size, pnaclProxy);
     else
       task = new EmscrTask(file.name, url, file.size, new Worker(emscrbin));

     addTask(task);
     estimateOutputSize(task);
       

   }
   
   void addTask(FileTask input){
     tasks[input.id] = input;
   }
   
   void removeTask(Event e, var details, Node target){
     tasks.remove(tasks[int.parse(details)]);
   }
   
   void estimateOutputSize(FileTask task){
     if(iz_app.runtime == RUNTIMETYPE.EMSCR)
       infoWorker.postMessage(new WorkerPostMessage.fromString("estimateOutputSize",task.id,task.inputSize.toString()));
     else{
       pnaclProxy.callMethod('postMessage', ['type\n'+MESSAGETYPE.ESTIMATESIZE.toString()+'\nid\n'+task.id.toString()+'\ninputSize\n'+task.inputSize.toString()]);
     }
   }
   
   void onEMSCREstimatedOutputSizeReceived(MessageEvent msgEvent){
     var wmsg = new WorkerReceivedMessage.fromJSON(msgEvent.data);
     int id_target = wmsg.callbackId;
     int size = int.parse(wmsg.message());
     tasks[id_target].estimatedOutputSize = size;
     iz_app.querySpaceAndRun(tasks[id_target]);
   }
   
   void showCompleteToast(int id){
     (this.shadowRoot.querySelector('#pt'+id.toString()) as PaperToast).show();
   }
   
   void onPTDownloadClick(Event e, var detail, Node target){
     //print('id'+(e.target as DivElement).id);
     int id = int.parse((e.target as DivElement).id.substring(2));
     iz_app.downloadTaskOutput(tasks[id]);
   }

  
  
   void querySpaceAndRun(FileTask taskToRun){
      if(currentBrowser == BROWSER.CHROME){
        if(!forcePersistent && taskToRun.estimatedSize<availableTempSpace-getTempUsedSpace())       
          taskToRun.start(FILESYSTEMTYPE.HTML5TEMP);     
        else{        
          switch(fs_pers_status){
            case FS_PERS_STATUS.CLOSED:
              fs_pers_status= FS_PERS_STATUS.OPENING;
              taskToRun.updateStatus(STATUSTYPE.WAITINGQUOTA.toString());
              window.navigator.persistentStorage.requestQuota(40*1024*1024*1024, 
                  (int received_size){
                     availablePersSpace = received_size;
                     fs_pers_status = FS_PERS_STATUS.OPENED;
                     this.tasks.forEach((k,v){
                       if((v as FileTask).status_id.toString()==STATUSTYPE.WAITINGQUOTA.toString())
                         querySpaceAndRun(v);
                           });
                         }, (e) {
                           print(e); 
                           availableTempSpace =0;
                           }
                         );
              break;
            case FS_PERS_STATUS.OPENING:
              taskToRun.updateStatus(STATUSTYPE.WAITINGQUOTA.toString());
              break;
            case FS_PERS_STATUS.OPENED:
              if(availablePersSpace-getPersUsedSpace()>taskToRun.estimatedSize)
                taskToRun.start(FILESYSTEMTYPE.HTML5PERS);
              else{
                tasksWaitingOutOfQuotaDialog.add(taskToRun);
              }
          }
            
        }
        
      }else{
        ///TODO: Add space management for MEMFS
        taskToRun.start(FILESYSTEMTYPE.MEMFS);
      }
  }
  
   
   int getTempUsedSpace(){
     uiUsedTemp = tasks.values.where((f)=>f.fs_location == FILESYSTEMTYPE.HTML5TEMP).fold(0, (a,b)=>a+b.taskSize);
     return uiUsedTemp;
   }
   
   int getPersUsedSpace(){
     uiUsedPers = tasks.values.where((f)=>f.fs_location == FILESYSTEMTYPE.HTML5PERS).fold(0, (a,b)=>a+b.taskSize);
        return uiUsedPers;
      }
  
  void OOQD_Wait(){
    tasksWaitingOutOfQuotaDialog.last.updateStatus(STATUSTYPE.WAITINGUSERCLICK.toString());
    tasksWaitingOutOfQuotaDialog.remove(tasksWaitingOutOfQuotaDialog.last);
  }
  
  void OOQD_Force(){
      querySpaceAndRun(tasksWaitingOutOfQuotaDialog.last);
      tasksWaitingOutOfQuotaDialog.remove(tasksWaitingOutOfQuotaDialog.last);
    }
  
  void downloadTaskOutput(FileTask t){
    var a = new AnchorElement(href: t.output_file_url)..attributes.addAll({'Download':t.output_file_name});
          document.body.children.add(a);
          a.click();
          t.downloaded=true;
  }
   
  void onForcePersistentClick(){
    forcePersistent = !forcePersistent;
  }
  
  void onCompatiblityModeClick(){
    toggleOption('compatibilitymode');
    window.location.reload();
  }
  
  void setOption(String key, [String value='']){
    if(options.containsKey(key))
            options.remove(key);
    options.addAll({key:value}); 
    window.history.replaceState({}, '',appUrl.path+optionsToFragments());
  }
  
  void removeOption(String key){
      if(options.containsKey(key)){
        options.remove(key);
        window.history.replaceState({}, '',appUrl.path+optionsToFragments());
      }
    }
  
  void toggleOption(String key, [String value='']){
    if(options.containsKey(key))
      removeOption(key);
    else
      setOption(key, value);   
  }
  
  String optionsToFragments(){
    String fragments='';
        if(options.isNotEmpty)
           fragments= '#';
        options.forEach((k,v){
          fragments+=k;
          if(v!= '')
            fragments+='='+v;
          fragments+=';';
        });
        return fragments;
  }
  
  void onPurgeEverythingClick(){
    tasks.forEach((k,v)=>v.cancel());
    Html5FS.temp().then((fs)=>fs.root.getDirectory('/InputZone').then((e)=> e.removeRecursively()));
    Html5FS.pers().then((fs)=>fs.root.getDirectory('/InputZone').then((e)=> e.removeRecursively()));
  }
  
  void onAboutClick(){
    t_e_l='+'+'33'+' 6 23'+' 72';
    t_e_l+=' 15 96';
    ($['AboutDialog'] as PaperDialog).toggle();
  }
  
  void onSearchInput(Event e, var details, Node target){
    ($['register'] as IzRegister).filter((target as PaperInput).inputValue);
  }
  
  void onLogoClick(){
    window.location.href = "/";
  }
  
  void expandDrawer(){
    ($['drawer'] as CoreDrawerPanel).togglePanel();
  }
  
  void detectBrowser(){
    if(browser.isChrome)
      currentBrowser = BROWSER.CHROME;
    else if(browser.isFirefox)
      currentBrowser = BROWSER.FIREFOX;
    else if(browser.isOpera)
      currentBrowser = BROWSER.OPERA;
    else if(browser.isSafari)
      currentBrowser = BROWSER.SAFARI;
    else if(browser.isIe)
      currentBrowser = BROWSER.INTERNETEXPLORER;
    else
      currentBrowser = BROWSER.UNKNOWN;
  }
}

