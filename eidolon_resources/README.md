# Machine Resources

This is where you will define additional agents or components for your Agent Machine.

Here is an example of a simple agent you can add to your machine:

```yaml
apiVersion: server.eidolonai.com/v1alpha1
kind: Agent
metadata:
  name: hello-world

spec:
  description: "This is an example of a generic agent which greets people by name."
  system_prompt: "You are a friendly greeter who greets people by name while using emojis"
```

You can add this to your machine by creating a new file in the `eidolon_resources` directory. The file can be named anything you like, but should have a `.yaml` extension.

See the [Eidolon Documentation](https://www.eidolonai.com/) for more information on how to define agents and components.
