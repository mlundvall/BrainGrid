package edu.uwb.braingrid.data.script;

import com.hp.hpl.jena.rdf.model.Resource;
import com.jcraft.jsch.JSchException;
import com.jcraft.jsch.SftpException;
import edu.uwb.braingrid.provenance.ProvMgr;
import edu.uwb.braingrid.provenance.workbenchprov.WorkbenchOperationRecorder;
import edu.uwb.braingrid.workbench.FileManager;
import edu.uwb.braingrid.workbench.comm.SecureFileTransfer;
import edu.uwb.braingrid.workbench.data.OutputAnalyzer;
import edu.uwb.braingrid.workbench.model.ExecutedCommand;
import edu.uwb.braingrid.workbench.model.SimulationSpecification;
import edu.uwb.braingrid.workbench.ui.LoginCredentialsDialog;
import edu.uwb.braingrid.workbench.utils.DateTime;
import java.awt.Desktop;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Date;
import java.util.List;

/**
 * Manages script creation, script execution, and script output analysis.
 *
 * @author Del Davis
 */
public class ScriptManager {

    private String outstandingMessages;

    public ScriptManager() {
        outstandingMessages = "";
    }

    /**
     * Generates a constructed (but not persisted) Script
     *
     * @param projectname
     * @param version The version of the script (used in tracing output back to
     * the script that printed the output)
     * @param simSpec - The specification for the simulator to execute in the
     * script
     * @param simConfigFilename
     * @return A constructed script or null in the case that the script could
     * not be constructed properly
     */
    public static Script generateScript(String projectname, String version, SimulationSpecification simSpec, String simConfigFilename) {
        boolean success;
        simConfigFilename = FileManager.getSimpleFilename(simConfigFilename);
        // create a new script
        Script script = new Script(version);
        /* Print Header Data */
        script.printf(Script.versionText, version, null, false);
        // determine which simulator file to execute
        String type = simSpec.getSimulationType();
        String simExecutableToInvoke;
        simExecutableToInvoke = SimulationSpecification.getSimFilename(type);
        success = simExecutableToInvoke != null;
        printfSimSpecToScript(script, simExecutableToInvoke, simConfigFilename, true);
        /* Prep From ProjectMgr Data */
        // folder to change directory to for compilation and simulation execution
        String simFolder = simSpec.getSimulatorFolder();
        // central repository location
        String repoURI = simSpec.getCodeLocation();
        // git pull or do we assume it exists as is?
        String simulatorSourceCodeUpdatingType = simSpec.getSourceCodeUpdating();
        boolean updateRepo = false;
        if (simulatorSourceCodeUpdatingType != null) {
            updateRepo = simulatorSourceCodeUpdatingType.
                    equals(SimulationSpecification.GIT_PULL_AND_CLONE);
        }
        /* Create Script */
        // add a mkdir that will create intermediate directories
        String[] argsForMkdir = {"-p", simSpec.getSimulatorFolder()};
        script.executeProgram("mkdir", argsForMkdir);
        // do a pull?
        if (updateRepo) {
            // first do a clone and maybe fail
            String[] gitCloneArgs = {"clone", repoURI, simFolder};
            script.executeProgram("git", gitCloneArgs);
            // change directory to do a pull 
            // note: unnecessary with git 1.85 or higher, but git hasn't been 
            // updated in quite some time on the UWB root binaries :(
            String[] cdArg = {simFolder};
            script.executeProgram("cd", cdArg);
            // then do a pull and maybe fail (one of the two will work)
            String[] gitPullArgs = {"pull"};
            script.executeProgram("git", gitPullArgs);
        } else {
            String[] cdArg = {simFolder};
            script.executeProgram("cd", cdArg);
        }
//        /* Checkout Refactor */
//        String[] gitCheckoutRefactorArgs = {"checkout", "refactor-stable-cuda"};
//        script.executeProgram("git", gitCheckoutRefactorArgs);
        /* Make the Simulator */
        String[] cleanMakeArgs = {"-s", "clean"};
        script.executeProgram("make", cleanMakeArgs);
        String[] makeArgs = {"-s", simExecutableToInvoke, "CUSEHDF5='no'"};
        script.executeProgram("make", makeArgs);

        /* Make Results Folder */
        String[] mkResultsDirArgs = {"results"};
        script.executeProgram("mkdir", mkResultsDirArgs);
        script.addVerbatimStatement("mkdir -p workbenchconfigfiles/NList", null, true);
        /* Move Sim Config File */
        script.addVerbatimStatement("cp ~/" + simConfigFilename + " ~/"
                + simSpec.getSimulatorFolder()
                + "/workbenchconfigfiles/" + simConfigFilename, null, true);
        /* Move Neuron Lists */
        FileManager fm = FileManager.getFileManager();
        try {
            String[] nListFilenames = fm.getNeuronListFilenames(projectname);
            if (nListFilenames != null) {
                for (int i = 0, im = nListFilenames.length; i < im; i++) {
                    script.addVerbatimStatement("cp ~/"
                            + FileManager.getSimpleFilename(nListFilenames[i])
                            + " ~/"
                            + simSpec.getSimulatorFolder()
                            + "/workbenchconfigfiles"
                            + "/NList/"
                            + FileManager.getSimpleFilename(nListFilenames[i]), null,
                            true);
                }
            }
        } catch (IOException e) {
            success = false;
        }
        /* Run the Simulator */
        script.addVerbatimStatement("./" + simExecutableToInvoke
                + " -t workbenchconfigfiles/" + simConfigFilename, "~/simOutput"
                + version + ".out", true);
        /* Put Script Together and Save */
        if (!success || !script.construct()) {
            script = null; // or indicate unsuccessful operation
        }
        return script;
    }

    /**
     * Provides a string representation of the path to the folder where script
     * related files are stored
     *
     * @param projectFolder - A string representation of the path to the folder
     * where projects are stored (in relation to where the workbench was invoked
     * this is: ./projects/the_project_name/scripts/. However, this is system
     * dependent)
     * @return A string representation of the path to the folder where script
     * related files are stored. Depending on the form of the project folder
     * provided, this may represent a relative path.
     */
    public static String getScriptFolder(String projectFolder) {
        return projectFolder + "scripts"
                + FileManager.getFileManager().getFolderDelimiter();
    }

    /**
     * Runs the script as specified in the associated simulation specification.
     *
     * @param provMgr - Manages provenance. Used to record operations executed
     * from script.
     * @param simSpec - Holds information about the simulation
     * @param scriptPath - indicates where the constructed script to execute
     * resides on the file system.
     * @param scriptVersion
     * @param nListFilenames - Neuron lists indicated in simulation
     * configuration file.
     * @param simConfigFilename - Name of file containing simulation constants
     * and filenames. File, itself, is used to specify all input for a
     * simulation.
     * @return True if all operations associated with running the script were
     * successful, otherwise false. Note: This does not indicate whether the
     * simulation ran successfully
     * @throws com.jcraft.jsch.JSchException
     * @throws java.io.FileNotFoundException
     * @throws com.jcraft.jsch.SftpException
     */
    public boolean runScript(ProvMgr provMgr, SimulationSpecification simSpec,
            String scriptPath, String scriptVersion, String[] nListFilenames,
            String simConfigFilename)
            throws JSchException, FileNotFoundException, SftpException {
        boolean success;
        String executionMachine = simSpec.getSimulationLocale();
        String remoteExecution = SimulationSpecification.REMOTE_EXECUTION;
        // run script remotely?
        if (executionMachine.equals(remoteExecution)) {
            success = runRemoteScript(provMgr, simSpec, scriptPath,
                    scriptVersion, nListFilenames, simConfigFilename);
        } else { // or run it locally
            //if (!FileManager.getFileManager().isWindowsSystem()) {
            success
                    = runLocalScript(provMgr, simSpec, scriptPath, scriptVersion,
                            nListFilenames, simConfigFilename);
            //}
        }
        return success;
    }

    /**
     * Analyzes script output for provenance data. Relays that data to the
     * provenance manager. Note: This class defines the context between
     * provenance data. The provenance manager is used to connect such data as
     * determined by this function. This means that if script generation changes
     * this function may need to change, in turn, and vice-versa.
     *
     * @param simSpec - Specification used to indicate the context in which the
     * simulation was specified when the script was generated
     * @param prov - Provenance manager used to create provenance based on
     * analysis of the printf output
     * @param outputTargetFolder - location to store the redirected printf
     * output.
     * @return time completed in seconds since the epoch, or an error code
     * indicating that the script has not completed
     * @throws com.jcraft.jsch.JSchException
     * @throws com.jcraft.jsch.SftpException
     * @throws java.io.IOException
     */
    public long analyzeScriptOutput(SimulationSpecification simSpec, ProvMgr prov,
            String outputTargetFolder) throws JSchException, SftpException, IOException {
        long timeCompleted = DateTime.ERROR_TIME;
        String localOutputFilename
                = fetchScriptOutputFiles(simSpec, outputTargetFolder);
        if (localOutputFilename != null) {
            OutputAnalyzer analyzer = new OutputAnalyzer();
            analyzer.analyzeOutput(localOutputFilename);
            /* Completed */
            long atTime;
            String simExec = simSpec.getSimExecutable();
            atTime = analyzer.completedAt("./" + simExec);
            timeCompleted = atTime;
            if (timeCompleted != DateTime.ERROR_TIME) {
                /* Set Remote Namespace Prefix */
                if (simSpec.isRemote()) {
                    prov.setNsPrefix("remote", simSpec.getHostAddr());
                }
                /* Simulation */
                ExecutedCommand sim = analyzer.getFirstCommand("./" + simExec);
                if (sim != null) {
                    // get agent resource
                    String uri = simSpec.getSimulatorFolder() + "/" + simExec;
                    Resource simAgent = prov.addSoftwareAgent(uri, "simulator",
                            simSpec.isRemote());
                    // get activity resource
                    Resource simActivity = prov.addActivity("simulation", null,
                            simSpec.isRemote());
                    // connect the two
                    Resource associatedWith = prov.associateWith(simActivity,
                            simAgent);
                    prov.startedAtTime(simActivity, new Date(atTime).toString());
                }
                String scriptName = Script.getFilename(
                        analyzer.getScriptVersion());
                System.err.println(scriptName);
                //git log --pretty=format:'%h' -n 1
                SimulationSpecification spec = analyzer.getSimSpec();
                System.err.println(simSpec.getSimExecutable());
                List<ExecutedCommand> allCommandsList = null;
                Collection<ExecutedCommand> allCommands
                        = analyzer.getAllCommands();
                if (allCommands != null) {
                    allCommandsList = new ArrayList(allCommands);
                }
                if (allCommandsList != null) {
                    for (ExecutedCommand ec : allCommandsList) {
                        System.err.println(ec);
                    }
                }
                // collect output file and standard output redirect file
            }
        }
        return timeCompleted;
    }

    /**
     * Gets the messages that have accumulated within a public function call.
     * The accumulated messages are discarded during this call.
     *
     * @return The messages that have accumulated since the last call to this
     * function in the form of a single String.
     */
    public String getOutstandingMessages() {
        String msg = outstandingMessages;
        outstandingMessages = "";
        return msg;
    }

    private static void printfSimSpecToScript(Script script, String simFile, String simInputFilename, boolean append) {
        script.printf(SimulationSpecification.simExecText, simFile, null,
                append);
        String joinedInputs = simInputFilename;
        script.printf(SimulationSpecification.simInputsText, joinedInputs, null, true);
        // printf the outputs
        script.printf(SimulationSpecification.simOutputsText, "output.xml", null, true);
        // printf the end tag for the sim spec data
        script.printf(SimulationSpecification.endSimSpecText, "", null, true);
    }

    private boolean runRemoteScript(ProvMgr provMgr, SimulationSpecification simSpec,
            String scriptPath, String scriptVersion, String[] nListFilenames,
            String simConfigFilename) throws JSchException,
            FileNotFoundException, SftpException {
        char[] password = null;
        boolean success = true;
        String hostname = simSpec.getHostAddr();
        // get username and password
        LoginCredentialsDialog lcd = new LoginCredentialsDialog(
                hostname, true);
        if (lcd.okClicked()) {
            SecureFileTransfer sft = new SecureFileTransfer();
            password = lcd.getPassword();
            lcd.clearPassword();
            String uploadStartTime = new Date().toString();
            /* Upload Script */
            if (sft.uploadFile(scriptPath, "", hostname, lcd.getUsername(),
                    password, null)) {
                // record upload provenance
                if (null != provMgr) {
                    WorkbenchOperationRecorder.uploadFile(provMgr, scriptPath,
                            "~/" + FileManager.getSimpleFilename(scriptPath),
                            "script", simSpec.getHostAddr(), "uploadScript_v"
                            + scriptVersion, uploadStartTime, new Date().toString());
                }
                outstandingMessages += "\n" + scriptPath + " uploaded to\n"
                        + hostname + "\n";

                String filename;
                boolean loopSuccess;
                /* Upload Neuron List Files */
                if (nListFilenames != null) {
                    for (int i = 0, im = nListFilenames.length; i < im;
                            i++) {
                        filename
                                = FileManager.getSimpleFilename(nListFilenames[i]);
                        outstandingMessages += "\n" + "Uploaded "
                                + nListFilenames[i] + " to\n" + hostname
                                + "\n";
                        uploadStartTime = new Date().toString();
                        loopSuccess = sft.uploadFile(nListFilenames[i], "",
                                hostname, lcd.getUsername(), password,
                                null);
                        if (!loopSuccess) {
                            success = false;
                            outstandingMessages += "\n" + "Problem uploading "
                                    + nListFilenames[i] + " to\n" + hostname
                                    + "\n";
                            break;
                        } else {
                            outstandingMessages += "\n" + filename
                                    + " uploaded to\n"
                                    + hostname + "\n";
                            // record upload provenance
                            if (provMgr != null) {
                                WorkbenchOperationRecorder.uploadFile(provMgr,
                                        nListFilenames[i], "~/"
                                        + FileManager.getSimpleFilename(nListFilenames[i]),
                                        "nlist", simSpec.getHostAddr(), "uploadNList_"
                                        + i + "_forScript_v"
                                        + scriptVersion, uploadStartTime, new Date().toString());
                            }
                        }
                    }
                }
                /* Upload Simulation Configuration File */
                if (success) {
                    uploadStartTime = new Date().toString();
                    success = sft.uploadFile(simConfigFilename, "", hostname,
                            lcd.getUsername(), password, null);
                    if (success) {
                        if (provMgr != null) {
                            WorkbenchOperationRecorder.uploadFile(provMgr,
                                    simConfigFilename, "~/"
                                    + FileManager.getSimpleFilename(simConfigFilename),
                                    "simulationConfigurationFile", simSpec.getHostAddr(), "upload_SimConfig_forScript_v"
                                    + scriptVersion, uploadStartTime, new Date().toString());
                        }
                        outstandingMessages += "\n"
                                + FileManager.getSimpleFilename(simConfigFilename)
                                + " uploaded to\n"
                                + hostname + "\n";
                    } else {
                        outstandingMessages += "\n" + "Problem uploading "
                                + FileManager.getSimpleFilename(simConfigFilename)
                                + " to\n" + hostname
                                + "\n";
                    }
                }
                /* Execute Script */
                if (success) {
                    String cmd = "nohup sh ./"
                            + FileManager.getSimpleFilename(scriptPath)
                            + " &";
                    outstandingMessages += "\n" + "Executing " + cmd
                            + " at\n"
                            + hostname + "\n";
                    sft.executeCommand(cmd, hostname, lcd.getUsername(),
                            password, false);
                    success = true;
                }
            } else {
                outstandingMessages += "\n" + "Failed to upload script to "
                        + hostname + "\n";
            }
        } else {
            outstandingMessages += "\n"
                    + "\nRemote Credentials Specification Cancelled\n";
        }
        outstandingMessages += "\n" + "Remote Operations Completed: "
                + new Date()
                + "\n";

        if (password != null) {
            Arrays.fill(password, '0');
        }

        return success;
    }

    private boolean runLocalScript(ProvMgr provMgr, SimulationSpecification simSpec,
            String scriptLocation, String scriptVersion, String[] inputFilenames,
            String simConfigFilename) {
        boolean success = true;
        String copyStartTime;
        FileManager fm = FileManager.getFileManager();
        Path scriptSourcePath = Paths.get(scriptLocation);
        // get the location where the script will execute  
        Path scriptTargetPath = Paths.get(fm.getUserDir()
                + FileManager.getSimpleFilename(scriptLocation));
        Path simConfigSourcePath = Paths.get(simConfigFilename);
        Path simConfigTargetPath = Paths.get(fm.getUserDir()
                + FileManager.getSimpleFilename(simConfigFilename));
        Path[] nListSourcePaths = null;
        Path[] nListTargetPaths = null;
        if (inputFilenames != null && inputFilenames.length > 0) {
            nListSourcePaths = new Path[inputFilenames.length];
            nListTargetPaths = new Path[inputFilenames.length];
            for (int i = 0, im = inputFilenames.length; i < im; i++) {
                nListSourcePaths[i] = Paths.get(inputFilenames[i]);
            }
            for (int i = 0, im = inputFilenames.length; i < im; i++) {
                nListTargetPaths[i] = Paths.get(fm.getUserDir()
                        + FileManager.getSimpleFilename(inputFilenames[i]));
            }
        }
        try {
            copyStartTime = new Date().toString();
            // copy the script
            FileManager.copyFile(scriptSourcePath, scriptTargetPath);
            // record provenance for copy operation
            if (provMgr != null) {
                WorkbenchOperationRecorder.copyFile(provMgr, scriptSourcePath.toString(),
                        scriptTargetPath.toString(), "script", "copy_Script_v"
                        + scriptVersion, copyStartTime, new Date().toString());
            }
            outstandingMessages += "\nFile copied..."
                    + "\nFrom: " + scriptSourcePath
                    + "\nTo: " + scriptTargetPath + "\n";
        } catch (IOException e) {
            outstandingMessages += "\n"
                    + "An IOException prevented the script from being copied..."
                    + "\nFrom: " + scriptSourcePath
                    + "\nTo: " + scriptTargetPath
                    + "\n";
        }
        // copy the input configuration file
        try {
            if (simConfigSourcePath != null && simConfigTargetPath != null) {
                copyStartTime = new Date().toString();
                FileManager.copyFile(simConfigSourcePath, simConfigTargetPath);
                // record file copy provenance for sim config file
                if (provMgr != null) {
                    WorkbenchOperationRecorder.copyFile(provMgr,
                            simConfigSourcePath.toString(),
                            simConfigTargetPath.toString(),
                            "simulationConfigurationFile",
                            "copy_SimConfig_forScript_v", copyStartTime,
                            new Date().toString());
                }
                outstandingMessages += "\nFile copied..."
                        + "\nFrom: " + simConfigSourcePath
                        + "\nTo: " + simConfigTargetPath + "\n";
            }
        } catch (IOException e) {
            outstandingMessages += "\n"
                    + "An IOException prevented the simulation configuration "
                    + "file from being copied"
                    + "\nFrom: " + simConfigSourcePath
                    + "\nTo :" + simConfigTargetPath
                    + "\n";
        }
        try {
            // copy the neuron list files specified in the config file
            if (nListSourcePaths != null && nListTargetPaths != null) {
                for (int i = 0, im = nListSourcePaths.length, in
                        = nListSourcePaths.length; i < im && i < in; i++) {
                    copyStartTime = new Date().toString();
                    FileManager.copyFile(nListSourcePaths[i], nListTargetPaths[i]);
                    if (provMgr != null) {
                        WorkbenchOperationRecorder.copyFile(provMgr,
                                nListSourcePaths[i].toString(),
                                nListTargetPaths[i].toString(), "nlist",
                                "uploadNList_" + i + "forScript_v"
                                + scriptVersion, copyStartTime, new Date().toString());
                    }
                    outstandingMessages += "\nFile copied..."
                            + "\nFrom: " + nListSourcePaths[i]
                            + "\nTo: " + nListTargetPaths[i]
                            + "\n";
                }
            }
        } catch (IOException e) {
            outstandingMessages += "\n"
                    + "An IOException prevented the following files: ";
            for (int i = 0, im = inputFilenames.length; i < im; i++) {
                if (i == im - 1 && i > 0) {
                    outstandingMessages += " and " + inputFilenames[i];
                } else {
                    outstandingMessages += inputFilenames[i] + ", ";
                }
            }
            outstandingMessages += " from being copied to: " + fm.getUserDir();
        }
        String oldWrkDir = System.getProperty("user.dir");
        String cmd = "sh " + System.getProperty("user.home")
                + FileManager.getSimpleFilename(scriptTargetPath.toString());
        // run the script
        try {
            if (fm.isWindowsSystem()) {
                System.setProperty("user.dir", System.getProperty("user.home"));

                if (Desktop.isDesktopSupported()) {
                    Desktop dt = Desktop.getDesktop();
                    dt.open(scriptTargetPath.toFile());
                }
            } else {
                Runtime.getRuntime().exec(cmd);
            }
        } catch (SecurityException e) {
            success = false;
            outstandingMessages += "\n"
                    + "A SecurityException prevented the script from execution"
                    + "\nAt: " + scriptTargetPath
                    + "\n";
        } catch (IOException e) {
            success = false;
            outstandingMessages += "\n"
                    + "An input/output error occured while executing: "
                    + "\n" + scriptTargetPath
                    + "\n";
            e.printStackTrace();
        } finally {
            System.setProperty("user.dir", oldWrkDir);
        }

        return success;
    }

    private String fetchScriptOutputFiles(SimulationSpecification simSpec,
            String outputStorageFolder) throws JSchException, SftpException, IOException {
        String filename = null;
        char[] password = null;
        String provFileTargetLocation = outputStorageFolder
                + Script.printfOutputFilename;
        // run simulation here or on another machine?
        boolean remote = simSpec.isRemote();
        if (remote) {
            // download prov.txt
            SecureFileTransfer sft = new SecureFileTransfer();
            String hostname = simSpec.getHostAddr();
            LoginCredentialsDialog lcd
                    = new LoginCredentialsDialog(hostname, true);
            password = lcd.getPassword();
            lcd.clearPassword();
            if (sft.downloadFile(Script.printfOutputFilename, provFileTargetLocation,
                    hostname, lcd.getUsername(), password)) {
                filename = provFileTargetLocation;
                sft.downloadFile(Script.printfOutputFilename, provFileTargetLocation,
                        hostname, lcd.getUsername(), password);
            }
        } else {
            FileManager fm = FileManager.getFileManager();
            String simFolder = simSpec.getSimulatorFolder();
            Path provSourcePath = Paths.get(fm.getUserDir()
                    + fm.getFolderDelimiter()
                    + Script.printfOutputFilename);
            Path provTargetPath = Paths.get(provFileTargetLocation);
            System.err.println(provSourcePath);
            System.err.println(provTargetPath);
            if (FileManager.copyFile(provSourcePath,
                    Paths.get(provFileTargetLocation))) {
                filename = provFileTargetLocation;
            }
        }
        if (password != null) {
            Arrays.fill(password, '0');
        }
        return filename;
    }
}
