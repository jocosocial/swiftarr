Deployment at Sea
=================



### Offline Incremental Builds

You will have had to go through an online build at least once in order for this to work.

Docker will cache:
* The bage images (`swift`, `ubuntu`, `postgres`, etc).
* The layers in which we install packages from Apt repos.

But this leaves local Swift package caching. There are a couple files that get seeded 
into `./.build` when you do a local build (`swift build` or `vapor build` from a dev machine)
that we can put in place to ensure an offline Docker-based build will also work. Specifically
they are:
* `./build/workspace-state.json`
* `./build/checkouts`

The `Dockerfile.stack` will automatically attempt to copy them into the image build
context if they exist. As long as they don't change that image layer will cache and
and there will be a performance benefit in doing incremental Docker builds. Otherwise
it'll just have to copy them into a new builder image (not the end of the world).

To seed your `./build` directory you can do one of two things:
01. Perform a local build.
02. Extract the `/app/.build` contents from a previous Docker build.

To achieve the second option above:
01. Do an online Docker build.

    ```
    scripts/stack.sh -e production build
    ```

02. Look in the log for the image ID of the builder that it used. In this example it is `74f20d50b6a6`.
    ```
	[950/951] Compiling Redis Application+Redis.swift
    remark: Incremental compilation has been disabled: it is not compatible with whole module optimization[952/953] Compiling App AdminController.swift
    remark: Incremental compilation has been disabled: it is not compatible with whole module optimization[954/955] Compiling Run main.swift
    [956/956] Linking Run
    [956/956] Build complete!
    Removing intermediate container f9ead447694a
    ---> 74f20d50b6a6 ### HEY THIS IS THE IMAGE ID YOU SEEK ###
    Step 13/29 : FROM ubuntu:18.04 as base
    ---> 886eca19e611
    ```

03. Create a temporary container based on that image to copy the files from. It helps to give it a human name but that is optional.
	 ```
    docker run --name buildertemp 74f20d50b6a6
    ```

    This will detatch and exist in the background. We will delete it later but if you get distracted you're on your own for cleanup.

04. Extract the package and workspace state. Note the trailing slash on the destination.
    ```
    mkdir ./.build
    docker cp buildertemp:/app/.build/workspace-state.json ./.build/
    docker cp buildertemp:/app/.build/checkouts ./.build/
    ```

05. Verify that you now have a `./.build` that looks like this:
    ```
    ls -l .build
    total 16K
    drwxr-xr-x. 29 grant grant 4.0K Jan 27 14:13 checkouts
    -rw-r--r--.  1 grant grant 8.9K Jan 27 14:13 workspace-state.json
    ```

06. Stop and remove the temporary container since we don't need it anymore.
    ```
    docker rm buildertemp
    ```

Once this is complete if you were to re-run the `scripts/stack.sh -e production build` it would trigger a new build since the builder will
detect that you've changed the source of the Swift dependencies (from internet pulls to local files). It will want to rebuild but you'll be able to do so without downloading anything from the internet. This can be observed by initiating the build and doing a packet capture against it. For example:
```
# In terminal #1
scripts/stack.sh -e production build

# In terminal #1
docker ps
docker inspect ${name_or_id_of_the_running_builder_container} | grep IPAddress
sudo tcpdump -nn -i any host 172.17.0.2 # or whatever the IP is
```